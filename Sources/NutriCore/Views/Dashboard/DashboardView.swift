import SwiftUI
import SwiftData

// MARK: - Home
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @Query private var hydrations: [DailyHydration]
    @StateObject private var healthManager = HealthKitManager.shared

    var onSearch: () -> Void = {}
    var onRaw: () -> Void = {}
    @State private var showRawLog = false

    init(onSearch: @escaping () -> Void = {}, onRaw: @escaping () -> Void = {}) {
        self.onSearch = onSearch
        self.onRaw = onRaw
        // Rows back to the start of the month (eating cycle) or the week, whichever is earlier; at least 7 days for
        // the raw snapshot. "Today" is filtered in memory so the view survives midnight.
        let cal = Calendar.current, today = cal.startOfDay(for: .now)
        let month = cal.dateInterval(of: .month, for: today)?.start ?? today
        let week = cal.date(byAdding: .day, value: -6, to: today) ?? today
        let cutoff = min(month, week, EatingCycle.weekStart(for: today))
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= cutoff }, sort: \.date)
        _hydrations = Query(filter: #Predicate<DailyHydration> { $0.date >= cutoff }, sort: \.date)
    }

    private var baseGoals: NutrientGoals { profiles.first.map(NutrientGoals.from) ?? .default }
    private var goals: NutrientGoals {
        var g = baseGoals
        if profiles.first != nil, healthManager.todayActiveEnergy > 0 { g.calories += healthManager.todayActiveEnergy }
        return g
    }
    private var todaysMeals: [MealEntry] {
        let cal = Calendar.current; return meals.filter { cal.isDateInToday($0.date) }
    }
    private var weekMeals: [MealEntry] {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
        return meals.filter { $0.date >= start }
    }
    private var todaysHydration: DailyHydration? {
        hydrations.first(where: { Calendar.current.isDateInToday($0.date) })
    }

    /// Creates today's hydration row if it doesn't exist yet.
    private func ensureRecords() {
        if todaysHydration == nil { modelContext.insert(DailyHydration()) }
        try? modelContext.save()
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                AppBackdrop()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        HomeHeader(onSearch: onSearch)
                            .padding(.horizontal, Space.margin)
                            .padding(.top, 12)

                        CycleSection(cycle: EatingCycle(meals: meals, calorieGoal: baseGoals.calories,
                                                        todayProgress: progress))
                            .padding(.horizontal, Space.margin)
                            .padding(.top, 20)

                        CalorieRing(total: todaysMeals.totalCalories, goal: goals.calories)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                            .padding(.bottom, 28)

                        MacroGrid(items: [
                            ("Protein", todaysMeals.totalProtein, goals.protein),
                            ("Carbs", todaysMeals.totalCarbs, goals.carbohydrates),
                            ("Fat", todaysMeals.totalFat, goals.fat),
                        ])

                        MealsSection(meals: todaysMeals, onAdd: onSearch) { meal in
                            Haptics.success()
                            let name = meal.foodName.components(separatedBy: ",").first ?? meal.foodName
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { MealLogger.delete(meal, in: modelContext) }
                            ToastCenter.shared.show("Removed — \(name)")
                        }
                        .padding(.top, 32)

                        VStack(alignment: .leading, spacing: Space.section) {
                            if let hydration = todaysHydration {
                                HydrationSection(hydration: hydration,
                                    onAddWater: {
                                        hydration.waterOunces += 8.45
                                        try? modelContext.save()
                                        healthManager.saveDietaryWater(ounces: 8.45)
                                    },
                                    onAddSalt: { hydration.addedSodiumMg += 400; try? modelContext.save() })
                            }

                            RawSnapshotSection(meals: todaysMeals, weekMeals: weekMeals, onOpen: onRaw,
                                               onLogRaw: { showRawLog = true }, onSearch: onSearch)
                        }
                        .padding(.horizontal, Space.margin)
                        .padding(.top, 20)
                    }
                    .padding(.bottom, 120)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showRawLog) { NavigationStack { RawLogView() } }
            .task {
                ensureRecords()
                await healthManager.fetchTodayData()
                await SocialService.shared.backfill(meals)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    ensureRecords()
                    Task { await healthManager.fetchTodayData() }
                }
            }
        }
    }

    private var progress: Double { goals.calories > 0 ? todaysMeals.totalCalories / goals.calories : 0 }
}

// MARK: - Header
private struct HomeHeader: View {
    let onSearch: () -> Void
    private var dateText: String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: Date()).uppercased()
    }
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today").monoLabel()
                Text(dateText).font(.system(size: 22, weight: .bold)).tracking(0.44).foregroundColor(.ncPrimary)
            }
            Spacer()
            Button("Search", action: onSearch).buttonStyle(.glass)
        }
    }
}

// MARK: - Eating cycle
/// The cycle is the calendar month: one tick per day, past days marked by whether intake landed within
/// 85–110% of the calorie goal. Days with nothing logged stay neutral.
struct EatingCycle {
    enum Mark { case onTarget, offTarget, today, upcoming, empty }
    struct Day: Identifiable { let id: Date; let mark: Mark; let weekday: String; let number: Int }

    let day: Int
    let length: Int
    let ticks: [Mark]
    let week: [Day]

    static func weekStart(for date: Date) -> Date {
        var cal = Calendar(identifier: .iso8601); cal.timeZone = .current
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }

    init(meals: [MealEntry], calorieGoal: Double, todayProgress: Double, now: Date = .now) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var kcalByDay: [Date: Double] = [:]
        for meal in meals { kcalByDay[cal.startOfDay(for: meal.date), default: 0] += meal.calories }

        func mark(_ date: Date) -> Mark {
            if date == today { return .today }
            if date > today { return .upcoming }
            guard let kcal = kcalByDay[date], calorieGoal > 0 else { return .empty }
            let p = kcal / calorieGoal
            return (0.85...1.1).contains(p) ? .onTarget : .offTarget
        }

        let month = cal.dateInterval(of: .month, for: today)!
        length = cal.range(of: .day, in: .month, for: today)?.count ?? 30
        day = cal.component(.day, from: today)
        ticks = (0..<length).map { mark(cal.date(byAdding: .day, value: $0, to: month.start)!) }

        let start = Self.weekStart(for: today)
        let f = DateFormatter(); f.dateFormat = "EEE"
        week = (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            return Day(id: d, mark: mark(d), weekday: f.string(from: d).uppercased(), number: cal.component(.day, from: d))
        }
    }
}

private struct CycleSection: View {
    let cycle: EatingCycle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Eating cycle").monoLabel()
                Spacer()
                (Text("DAY \(cycle.day) ") + Text("OF \(cycle.length)").foregroundColor(.ncSecondary))
                    .font(.mono(12, .semibold)).tracking(0.96).foregroundColor(.ncPrimary)
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(cycle.ticks.enumerated()), id: \.offset) { _, mark in
                    Capsule().fill(tickColor(mark))
                        .frame(maxWidth: .infinity)
                        .frame(height: mark == .today ? 22 : 14)
                }
            }
            .frame(height: 22)
            .accessibilityElement()
            .accessibilityLabel("Day \(cycle.day) of \(cycle.length)")

            HStack(spacing: 6) {
                ForEach(cycle.week) { day in
                    let today = day.mark == .today
                    VStack(spacing: 6) {
                        Text(day.weekday).font(.mono(10, .semibold)).tracking(0.8).opacity(0.8)
                        Text("\(day.number)").font(.display(17))
                        Circle().fill(dotColor(day.mark)).frame(width: 6, height: 6)
                    }
                    .foregroundColor(today ? .ncOnPrimary : day.mark == .upcoming ? .ncSecondary : .ncPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10).padding(.bottom, 9)
                    .background(Capsule().fill(today ? Color.ncPrimary : Color.white.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(today ? Color.ncPrimary : Color.white.opacity(0.14), lineWidth: 1))
                }
            }
            .padding(.top, 4)

            HStack(spacing: 14) {
                legend(.ncMoss, "On target")
                legend(.ncEmber, "Under / over")
                legend(.ncPrimary.opacity(0.25), "Upcoming")
            }
        }
    }

    private func tickColor(_ m: EatingCycle.Mark) -> Color {
        switch m {
        case .onTarget: .ncMoss
        case .offTarget: .ncEmber
        case .today: .ncPrimary
        case .upcoming, .empty: .ncPrimary.opacity(0.16)
        }
    }
    private func dotColor(_ m: EatingCycle.Mark) -> Color {
        switch m {
        case .onTarget: .ncMoss
        case .offTarget: .ncEmber
        case .today: .ncOnPrimary
        case .upcoming, .empty: .ncPrimary.opacity(0.25)
        }
    }
    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text.uppercased()).font(.mono(10)).tracking(0.8).foregroundColor(.ncSecondary)
        }
    }
}

// MARK: - Calories
private struct CalorieRing: View {
    let total: Double
    let goal: Double
    private var progress: Double { goal > 0 ? total / goal : 0 }
    private var pct: Int { Int((min(progress, 1) * 100).rounded()) }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().strokeBorder(Color.ncPrimary.opacity(0.12), lineWidth: 14)
                Circle()
                    .inset(by: 7)
                    .trim(from: 0, to: min(progress, 1))
                    .stroke(Color.ncPrimary, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: progress)
                VStack(spacing: 6) {
                    Text(Int(total).formatted()).font(.display(52)).tracking(-2.08).foregroundColor(.ncPrimary)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: Int(total))
                    Text("OF \(Int(goal).formatted()) KCAL").font(.mono(12)).tracking(1.92).foregroundColor(.ncSecondary)
                }
            }
            .frame(width: 240, height: 240)
            .accessibilityElement(children: .combine)

            HStack(spacing: 24) {
                Text("\(pct)% OF GOAL").foregroundColor(.ncPrimary)
                Text("\(Int(max(0, goal - total)).formatted()) KCAL LEFT").foregroundColor(.ncSecondary)
            }
            .font(.mono(13)).tracking(1.04)
        }
    }
}

private struct MacroGrid: View {
    let items: [(String, Double, Double)]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Macros").monoLabel().padding(.horizontal, Space.margin)
            HStack(alignment: .top, spacing: 0) {
                ForEach(items, id: \.0) { label, cur, goal in
                    let p = goal > 0 ? cur / goal : 0
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label).font(.system(size: 13, weight: .bold)).foregroundColor(.ncPrimary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Int(cur.rounded()).formatted()).font(.system(size: 26)).foregroundColor(.ncPrimary)
                                .contentTransition(.numericText())
                            Text("/\(Int(goal.rounded()).formatted()) G").font(.mono(11)).foregroundColor(.ncSecondary)
                        }
                        LineGauge(value: p, height: 4).padding(.top, 4)
                        Text("\(Int((min(p, 1) * 100).rounded()))%").font(.mono(11)).foregroundColor(.ncSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20).padding(.trailing, 14)
                    .padding(.top, 16).padding(.bottom, 18)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Water & salt
private struct HydrationSection: View {
    let hydration: DailyHydration
    let onAddWater: () -> Void
    let onAddSalt: () -> Void
    private var liters: Double { hydration.waterOunces * 0.0295735 }
    private var salt: Double { hydration.addedSodiumMg / 1000.0 }

    var body: some View {
        RawCard(title: "Water & salt", trailing: "\(Int(min(liters / 3.5, 1) * 100))% of water", index: nil) {
            HStack(alignment: .top, spacing: 0) {
                column(label: "Water", value: String(format: "%.1f", liters), unit: "L", target: "of 3.5 L",
                       progress: liters / 3.5, button: "+ 250 ml", action: onAddWater)
                Rectangle().fill(Color.ncPrimary.opacity(0.14)).frame(width: 1).padding(.horizontal, 16)
                column(label: "Added salt", value: String(format: "%.1f", salt), unit: "g", target: "of 5 g",
                       progress: salt / 5, button: "+ 1 pinch", action: onAddSalt)
            }
        }
    }

    private func column(label: String, value: String, unit: String, target: String, progress: Double,
                        button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(label).serifCaps(10).foregroundColor(.ncSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.metric(34)).foregroundColor(.ncPrimary).contentTransition(.numericText())
                Text(unit).font(.serif(14)).foregroundColor(.ncSecondary)
            }
            .animation(.smooth, value: value)
            LineGauge(value: progress)
            Text(target).font(.system(size: 13)).foregroundColor(.ncSecondary)
            Button(action: action) { Text(button) }
                .buttonStyle(SecondaryButtonStyle(height: 40))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Raw snapshot
struct RawSnapshotSection: View {
    let meals: [MealEntry]
    let weekMeals: [MealEntry]
    let onOpen: () -> Void
    let onLogRaw: () -> Void
    let onSearch: () -> Void

    var body: some View {
        let rating = DietRater.rate(meals: weekMeals, days: 7)
        let budget = NutrientAnalyzer.liverBudget(weekMeals)
        let fat = NutrientAnalyzer.fatCaloriePct(meals)
        RawCard(title: "Raw & carnivore", trailing: "7 days", index: nil) {
            VStack(alignment: .leading, spacing: 24) {
                Button(action: onOpen) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(rating.tier.title).font(.serif(28)).foregroundColor(.ncPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 14)).foregroundColor(.ncSecondary)
                    }
                }
                .buttonStyle(.plain)
                SpectrumBar(position: rating.position, active: rating.tier != .insufficient)
                StatStrip(items: [
                    .init(label: "Fat share", value: fat.map { "\(Int($0))%" } ?? "—"),
                    .init(label: "Vitamin A", value: "\(Int(budget.vitaminAPct * 100))%"),
                    .init(label: "Raw", value: "\(Int(rating.rawPct))%"),
                ])
                HStack(spacing: 10) {
                    Button(action: onLogRaw) { Label("Log raw", systemImage: "plus") }.buttonStyle(.primal)
                    Button(action: onSearch) { Label("Search", systemImage: "magnifyingglass") }.buttonStyle(SecondaryButtonStyle(height: 54))
                }
            }
        }
    }
}

// MARK: - Meals
struct MealsSection: View {
    let meals: [MealEntry]
    let onAdd: () -> Void
    let onDelete: (MealEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Meals · \(meals.count)").monoLabel()
                Spacer()
                Button("+ Add food", action: onAdd).buttonStyle(TextButtonStyle(color: .ncPrimary))
            }
            .padding(.horizontal, Space.margin)

            VStack(spacing: 0) {
                Rule()
                if meals.isEmpty {
                    Text("Nothing logged yet today. Search, scan a barcode or photograph a meal to start.")
                        .font(.system(size: 15)).foregroundColor(.ncSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 28)
                } else {
                    ForEach(meals.reversed()) { meal in
                        MealRow(meal: meal) { onDelete(meal) }
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .move(edge: .leading))))
                    }
                }
            }
            .padding(.horizontal, Space.margin)

            Button("Log food", action: onAdd)
                .buttonStyle(.primal)
                .padding(Space.margin)
        }
    }
}

/// Time · name + portion · kcal · a visible 44 pt remove target (no hidden swipe).
struct MealRow: View {
    let meal: MealEntry
    let onDelete: () -> Void

    private var timeStr: String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: meal.date) }
    private var meta: String {
        var parts = ["\(Int(meal.servingSize)) g"]
        if !meal.source.isEmpty { parts.append(meal.source) }
        if meal.riskScore > 0 { parts.append("risk \(Int(meal.riskScore))") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(timeStr).font(.mono(12)).foregroundColor(.ncSecondary)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(meal.foodName.capitalized).font(.system(size: 15, weight: .bold)).foregroundColor(.ncPrimary).lineLimit(1)
                Text(meta).font(.system(size: 12)).foregroundColor(meal.riskScore >= 65 ? .ncEmber : .ncSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            (Text("\(Int(meal.calories).formatted())") + Text(" KCAL").foregroundColor(.ncSecondary))
                .font(.mono(13)).foregroundColor(.ncPrimary)
            Button(action: onDelete) {
                Text("×").font(.system(size: 22)).foregroundColor(.ncSecondary)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(meal.foodName)")
        }
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { Hairline(opacity: 0.28) }
        .accessibilityElement(children: .contain)
    }
}
