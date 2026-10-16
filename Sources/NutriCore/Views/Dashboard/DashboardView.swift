import SwiftUI
import SwiftData

// MARK: - Today
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @Query private var hydrations: [DailyHydration]
    @StateObject private var healthManager = HealthKitManager.shared

    var onProfile: () -> Void = {}
    var onRaw: () -> Void = {}
    @State private var showSearch = false
    @State private var showRawLog = false

    init(onProfile: @escaping () -> Void = {}, onRaw: @escaping () -> Void = {}) {
        self.onProfile = onProfile
        self.onRaw = onRaw
        // Only load recent rows (a week, for the raw snapshot); "today" is filtered in memory so the view survives midnight.
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= cutoff }, sort: \.date)
        _hydrations = Query(filter: #Predicate<DailyHydration> { $0.date >= cutoff }, sort: \.date)
    }

    private var goals: NutrientGoals {
        if let profile = profiles.first {
            var g = NutrientGoals.from(profile)
            if healthManager.todayActiveEnergy > 0 { g.calories += healthManager.todayActiveEnergy }
            return g
        }
        return NutrientGoals.default
    }
    private var todaysMeals: [MealEntry] {
        let cal = Calendar.current; return meals.filter { cal.isDateInToday($0.date) }
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
                    VStack(alignment: .leading, spacing: Space.section) {
                        TodayHeader(onProfile: onProfile)

                        EnergySection(
                            total: todaysMeals.totalCalories, goal: goals.calories,
                            protein: todaysMeals.totalProtein, proteinGoal: goals.protein,
                            fat: todaysMeals.totalFat, fatGoal: goals.fat,
                            carbs: todaysMeals.totalCarbs, carbGoal: goals.carbohydrates)

                        if let hydration = todaysHydration {
                            HydrationSection(hydration: hydration,
                                onAddWater: {
                                    hydration.waterOunces += 8.45
                                    try? modelContext.save()
                                    healthManager.saveDietaryWater(ounces: 8.45)
                                },
                                onAddSalt: { hydration.addedSodiumMg += 400; try? modelContext.save() })
                        }

                        RawSnapshotSection(meals: todaysMeals, weekMeals: meals, onOpen: onRaw,
                                           onLogRaw: { showRawLog = true }, onSearch: { showSearch = true })

                        MealsSection(meals: todaysMeals) { meal in
                            Haptics.success()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { MealLogger.delete(meal, in: modelContext) }
                        }
                    }
                    .padding(.horizontal, Space.margin)
                    .padding(.top, 12)
                    .padding(.bottom, 140)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSearch) { SearchView() }
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
}

// MARK: - Header
private struct TodayHeader: View {
    let onProfile: () -> Void
    private var dateText: String {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM"; return f.string(from: Date())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            HStack(alignment: .center) {
                Text(dateText).serifCaps(11).foregroundColor(.ncPrimary.opacity(0.8))
                Spacer()
                Button(action: onProfile) {
                    Image(systemName: "person")
                        .font(.system(size: 15, weight: .regular)).foregroundColor(.ncPrimary)
                        .frame(width: 44, height: 44)
                        .overlay(Rectangle().stroke(Color.ncPrimary.opacity(0.4), lineWidth: 1))
                }
                .smoothButton()
                .accessibilityLabel("Profile")
            }
            Wordmark(size: 86)
        }
    }
}

// MARK: - 01 Energy
private struct EnergySection: View {
    let total, goal, protein, proteinGoal, fat, fatGoal, carbs, carbGoal: Double
    private var progress: Double { goal > 0 ? total / goal : 0 }
    private var remaining: Int { Int(goal - total) }

    var body: some View {
        RawCard(title: "Energy", trailing: remaining >= 0 ? "\(remaining.formatted()) left" : "\((-remaining).formatted()) over",
                trailingColor: remaining >= 0 ? .ncSecondary : .ncError, index: "01") {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Metric(value: Int(total).formatted(), unit: "kcal", caption: "of \(Int(goal).formatted()) kcal today", size: 60)
                        .animation(.smooth, value: Int(total))
                    LineGauge(value: progress, tint: progress > 1 ? .ncError : .ncPrimary)
                }
                StatStrip(items: [
                    .init(label: "Protein", value: "\(Int(protein))g", note: "of \(Int(proteinGoal)) g", progress: proteinGoal > 0 ? protein / proteinGoal : 0),
                    .init(label: "Fat", value: "\(Int(fat))g", note: "of \(Int(fatGoal)) g", progress: fatGoal > 0 ? fat / fatGoal : 0),
                    .init(label: "Carbs", value: "\(Int(carbs))g", note: "of \(Int(carbGoal)) g", progress: carbGoal > 0 ? carbs / carbGoal : 0),
                ])
            }
        }
    }
}

// MARK: - 02 Water & salt
private struct HydrationSection: View {
    let hydration: DailyHydration
    let onAddWater: () -> Void
    let onAddSalt: () -> Void
    private var liters: Double { hydration.waterOunces * 0.0295735 }
    private var salt: Double { hydration.addedSodiumMg / 1000.0 }

    var body: some View {
        RawCard(title: "Water & salt", trailing: "\(Int(min(liters / 3.5, 1) * 100))% of water", index: "02") {
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

// MARK: - 03 Raw snapshot
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
        RawCard(title: "Raw & carnivore", trailing: "7 days", index: "03") {
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

// MARK: - 04 Meals
struct MealsSection: View {
    let meals: [MealEntry]
    let onDelete: (MealEntry) -> Void

    var body: some View {
        RawCard(title: "Today's meals", trailing: meals.isEmpty ? nil : "\(meals.count) logged", index: "04") {
            if meals.isEmpty {
                Text("Nothing logged yet. Scan, search or log a raw item to start the day.")
                    .font(.serif(15)).italic().foregroundColor(.ncSecondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(meals.reversed()) { meal in
                        MealRow(meal: meal) { onDelete(meal) }
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .move(edge: .leading))))
                    }
                }
            }
        }
    }
}

struct MealRow: View {
    let meal: MealEntry
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0

    private var timeStr: String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: meal.date) }
    private var meta: String {
        var parts: [String] = []
        if !meal.source.isEmpty { parts.append(meal.source) }
        if meal.riskScore > 0 { parts.append("risk \(Int(meal.riskScore))") }
        parts.append("P \(Int(meal.protein)) · F \(Int(meal.totalFat)) · C \(Int(meal.carbohydrates))")
        return parts.joined(separator: "  ·  ")
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < -20 {
                Button(action: { onDelete(); offset = 0 }) {
                    Text("Delete").spacedCaps(12).fontWeight(.bold).foregroundColor(.ncOnPrimary)
                        .padding(.horizontal, 20).frame(maxHeight: .infinity)
                        .background(Color.ncError)
                }
            }

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    Text(timeStr).font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundColor(.ncSecondary)
                        .frame(width: 44, alignment: .leading)
                        .padding(.top, 2)
                    if let data = meal.photoData, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFill().frame(width: 48, height: 48).clipped()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(meal.foodName.capitalized).font(.system(size: 17, weight: .medium)).foregroundColor(.ncPrimary).lineLimit(2)
                        Text(meta).font(.system(size: 12)).foregroundColor(meal.riskScore >= 65 ? .ncError : .ncSecondary).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(meal.calories))").font(.metric(18)).foregroundColor(.ncPrimary)
                        Text("kcal").font(.serif(12)).foregroundColor(.ncSecondary)
                    }
                }
                .padding(.vertical, 16)
                Hairline(opacity: 0.12)
            }
            .background(offset == 0 ? Color.clear : Color.ncBg)
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { if $0.translation.width < 0 { offset = $0.translation.width } }
                    .onEnded { value in
                        withAnimation(.spring()) { offset = value.translation.width < -50 ? -96 : 0 }
                    }
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Delete", onDelete)
    }
}
