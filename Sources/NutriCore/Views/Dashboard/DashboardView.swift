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
    @State private var showRawLog = false
    @State private var pushed: SecondaryScreen?
    @AppStorage(HealthPrimingView.pendingKey) private var healthPrimingPending = false

    init(onSearch: @escaping () -> Void = {}) {
        self.onSearch = onSearch
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
                        HomeHeader(onSearch: onSearch, onWeather: { pushed = .sun })
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

                            RawSnapshotSection(meals: todaysMeals, weekMeals: weekMeals, onOpen: { pushed = .raw },
                                               onLogRaw: { showRawLog = true })
                        }
                        .padding(.horizontal, Space.margin)
                        .padding(.top, 20)
                    }
                    .padding(.bottom, 120)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("Home") // names the back button on pushed screens
            .navigationDestination(item: $pushed) { $0.destination }
            .sheet(isPresented: $showRawLog) { NavigationStack { RawLogView() } }
            // Offered once after profile setup, explaining what's read and written before the system prompt.
            .sheet(isPresented: $healthPrimingPending) {
                HealthPrimingView { healthPrimingPending = false }
                    .presentationDetents([.large])
                    .presentationBackground(Color.ncBg)
            }
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
    let onWeather: () -> Void
    private var dateText: String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: Date()).uppercased()
    }
    var body: some View {
        // Date and buttons on one row when they fit; buttons drop below the date at large text sizes.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom) {
                date
                Spacer()
                actions
            }
            VStack(alignment: .leading, spacing: 12) {
                date
                actions
            }
        }
    }
    private var date: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dateText).font(.ui(size: 22, weight: .bold)).tracking(0.44).foregroundColor(.ncPrimary)
                .lineLimit(1).fixedSize()
        }
    }
    private var actions: some View {
        HStack(spacing: 10) {
            WeatherChip(onOpen: onWeather)
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium))
            }
            .buttonStyle(.glassDot)
            .accessibilityLabel("Search foods")
            .accessibilityShowsLargeContentViewer { Image(systemName: "magnifyingglass"); Text("Search") }
        }
    }
}

/// Current conditions as a glass dot beside Search: the SF Symbol over the temperature. Tapping opens the
/// Sun screen. Location is only requested when the user taps the dot, never on launch.
private struct WeatherChip: View {
    let onOpen: () -> Void
    @StateObject private var location = LocationManager(continuous: false)
    @ObservedObject private var weather = WeatherService.shared

    private var authorized: Bool {
        location.authorizationStatus == .authorizedWhenInUse || location.authorizationStatus == .authorizedAlways
    }

    var body: some View {
        Group {
            if authorized, let now = weather.current {
                Button(action: onOpen) {
                    dot(now.symbol, now.temperature)
                }
                .accessibilityShowsLargeContentViewer { Image(systemName: now.symbol); Text(now.temperature) }
                .accessibilityLabel("Weather: \(now.summary), \(now.temperature)")
                .accessibilityHint("Opens Sun")
            } else if authorized {
                // Loading. Always draw something: the fetch below is attached to this view, and SwiftUI
                // doesn't run tasks on an empty one.
                Button(action: onOpen) {
                    dot("cloud", "--°").opacity(0.5)
                }
                .accessibilityLabel("Weather loading")
            } else if location.authorizationStatus == .notDetermined {
                Button { location.requestPermission() } label: {
                    Image(systemName: "cloud.sun").font(.system(size: 17, weight: .regular))
                }
                .accessibilityLabel("Weather")
                .accessibilityHint("Asks for your location to show local weather")
            }
            // Denied or restricted: no chip.
        }
        .buttonStyle(.glassDot)
        .task(id: location.location?.coordinate.latitude) {
            if let loc = location.location { await weather.refresh(location: loc) }
        }
        // A fresh coarse fix each time Home appears; WeatherService skips the network if nothing changed.
        .onAppear { if authorized { location.requestOnce() } }
    }

    /// Symbol over temperature, sized to sit inside the 44 pt dot.
    private func dot(_ symbol: String, _ temperature: String) -> some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .frame(height: 17)
            Text(temperature)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
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
            (Text("DAY \(cycle.day) ") + Text("OF \(cycle.length)").foregroundColor(.ncSecondary))
                .font(.mono(12, .semibold)).tracking(0.96).foregroundColor(.ncPrimary)
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
                        Text(day.weekday).font(.mono(11, .semibold)).tracking(0.8).opacity(0.8)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("\(day.number)").font(.display(17))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Circle().fill(dotColor(day.mark)).frame(width: 6, height: 6)
                    }
                    .foregroundColor(today ? .ncOnPrimary : day.mark == .upcoming ? .ncSecondary : .ncPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10).padding(.bottom, 9)
                    .background(Capsule().fill(today ? Color.ncPrimary : Color.white.opacity(0.06)))
                    .overlay(Capsule().strokeBorder(today ? Color.ncPrimary : Color.white.opacity(0.14), lineWidth: 1))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.id.formatted(.dateTime.weekday(.wide))) \(day.number), \(markDescription(day.mark))")
                }
            }
            .padding(.top, 4)
            // Seven fixed columns can't grow with the text, so the row stops at the largest standard size.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

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
    private func markDescription(_ m: EatingCycle.Mark) -> String {
        switch m {
        case .onTarget: "on target"
        case .offTarget: "under or over target"
        case .today: "today"
        case .upcoming: "upcoming"
        case .empty: "nothing logged"
        }
    }
}

// MARK: - Calories
private struct CalorieRing: View {
    let total: Double
    let goal: Double
    private var progress: Double { goal > 0 ? total / goal : 0 }

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

            Text("\(Int(max(0, goal - total)).formatted()) KCAL LEFT")
                .font(.mono(13)).tracking(1.04).foregroundColor(.ncSecondary)
        }
    }
}

private struct MacroGrid: View {
    let items: [(String, Double, Double)]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(items, id: \.0) { label, cur, goal in
                    let p = goal > 0 ? cur / goal : 0
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label).font(.ui(size: 13, weight: .bold)).foregroundColor(.ncPrimary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Int(cur.rounded()).formatted()).font(.ui(size: 26)).foregroundColor(.ncPrimary)
                                .contentTransition(.numericText())
                            Text("/\(Int(goal.rounded()).formatted()) G").font(.mono(11)).foregroundColor(.ncSecondary)
                        }
                        LineGauge(value: p, height: 4).padding(.top, 4)
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
        RawCard {
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
            Text(target).font(.ui(size: 13)).foregroundColor(.ncSecondary)
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

    var body: some View {
        let rating = DietRater.rate(meals: weekMeals, days: 7)
        let budget = NutrientAnalyzer.liverBudget(weekMeals)
        let fat = NutrientAnalyzer.fatCaloriePct(meals)
        RawCard(title: "Raw & carnivore") {
            VStack(alignment: .leading, spacing: 24) {
                Button(action: onOpen) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(rating.tier.title).font(.serif(28)).foregroundColor(.ncPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.ui(size: 14)).foregroundColor(.ncSecondary)
                    }
                }
                .buttonStyle(.plain)
                SpectrumBar(position: rating.position, active: rating.tier != .insufficient)
                StatStrip(items: [
                    .init(label: "Fat share", value: fat.map { "\(Int($0))%" } ?? "—"),
                    .init(label: "Vitamin A", value: "\(Int(budget.vitaminAPct * 100))%"),
                    .init(label: "Raw", value: "\(Int(rating.rawPct))%"),
                ])
                Button(action: onLogRaw) { Label("Log raw", systemImage: "plus") }.buttonStyle(.vitalis)
            }
        }
    }
}

// MARK: - Meals
struct MealsSection: View {
    let meals: [MealEntry]
    let onAdd: () -> Void
    let onDelete: (MealEntry) -> Void
    /// Removing a meal is confirmed first: it also deletes it from Apple Health sharing and friends' feeds.
    @State private var pendingDelete: MealEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // With nothing logged there's no list to title; the Log food button below says what to do.
            if !meals.isEmpty {
                Text("Meals · \(meals.count)").monoLabel()
                    .padding(.horizontal, Space.margin)
                    .frame(minHeight: 44, alignment: .bottom)
            }

            VStack(spacing: 0) {
                if !meals.isEmpty {
                    Rule()
                    ForEach(meals.reversed()) { meal in
                        MealRow(meal: meal) { pendingDelete = meal }
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .move(edge: .leading))))
                            .contextMenu {
                                Button(role: .destructive) { pendingDelete = meal } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, Space.margin)

            Button("Log food", action: onAdd)
                .buttonStyle(.vitalis)
                .padding(Space.margin)
        }
        .confirmationDialog(
            "Remove \(pendingDelete.map { $0.foodName.components(separatedBy: ",").first ?? $0.foodName } ?? "meal")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { meal in
            Button("Remove", role: .destructive) { onDelete(meal) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It's removed from today's totals and from anything you've shared.")
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
                Text(meal.foodName.capitalized).font(.ui(size: 15, weight: .bold)).foregroundColor(.ncPrimary).lineLimit(1)
                Text(meta).font(.ui(size: 12)).foregroundColor(meal.riskScore >= 65 ? .ncEmber : .ncSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            (Text("\(Int(meal.calories).formatted())") + Text(" KCAL").foregroundColor(.ncSecondary))
                .font(.mono(13)).foregroundColor(.ncPrimary)
            Button(action: onDelete) {
                Text("×").font(.ui(size: 22)).foregroundColor(.ncSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(meal.foodName)")
            .accessibilityHint("Asks before removing")
        }
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { Hairline(opacity: 0.28) }
        .accessibilityElement(children: .contain)
    }
}
