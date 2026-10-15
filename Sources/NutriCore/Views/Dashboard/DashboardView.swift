import SwiftUI
import SwiftData

// MARK: - Dashboard (pixel-matched from "Autonomous Metabolic Intelligence" Light Theme)
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @Query private var hydrations: [DailyHydration]
    @StateObject private var healthManager = HealthKitManager.shared

    var onProfile: () -> Void = {}

    init(onProfile: @escaping () -> Void = {}) {
        self.onProfile = onProfile
        // Only load recent rows; "today" is filtered precisely in memory so the view survives midnight.
        let cutoff = Calendar.current.date(byAdding: .day, value: -2, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
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
                Color.ncBg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // ── Sticky Header ───────────────────────────────────
                        LightStitchHeader(onProfile: onProfile)
                            .padding(.top, 12)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)

                        // ── Calorie Clock ───────────────────────────────────
                        CalorieClockCard(
                            totalCalories: todaysMeals.totalCalories, goal: goals.calories,
                            protein: todaysMeals.totalProtein, proteinGoal: goals.protein,
                            fat: todaysMeals.totalFat, fatGoal: goals.fat,
                            carbs: todaysMeals.totalCarbs, carbGoal: goals.carbohydrates
                        )
                        .padding(.horizontal, 16)

                        // ── Hydration & Minerals ──────────────────────────
                        if let hydration = todaysHydration {
                            LightHydrationCard(hydration: hydration,
                                onAddWater: {
                                    hydration.waterOunces += 8.45
                                    try? modelContext.save()
                                    healthManager.saveDietaryWater(ounces: 8.45)
                                },
                                onAddSalt: { hydration.addedSodiumMg += 400; try? modelContext.save() }
                            )
                            .padding(.horizontal, 16)
                        }

                        // ── Automated Log (Meal Stream) ───────────────────
                        LightMealLogSection(meals: todaysMeals) { meal in
                            Haptics.success()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { MealLogger.delete(meal, in: modelContext) }
                        }
                        .padding(.horizontal, 16)

                        Spacer().frame(height: 110)
                    }
                }
            }
            .navigationBarHidden(true)
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
private struct LightStitchHeader: View {
    let onProfile: () -> Void
    @State private var pulse = false
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Text("Primal")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(.ncPrimary)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.ncIndigo)
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulse ? 1.4 : 1.0)
                        .opacity(pulse ? 0.5 : 1.0)
                    Text("AI active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.ncIndigo)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.ncIndigoLight)
                .cornerRadius(12)
                .onAppear { withAnimation(.easeInOut(duration: 1).repeatForever()) { pulse = true } }
            }
            Spacer()
            HStack(spacing: 12) {
                Button(action: onProfile) {
                    ZStack {
                        Circle().fill(Color.ncPrimary).frame(width: 32, height: 32)
                        Image(systemName: "person.fill").font(.system(size: 14)).foregroundColor(.ncOnPrimary)
                    }
                }
            }
        }
    }
}

// MARK: - Calorie Clock
/// Today's calories as a ring (like a clock face), with the macro split underneath.
struct CalorieClockCard: View {
    let totalCalories, goal, protein, proteinGoal, fat, fatGoal, carbs, carbGoal: Double

    private var progress: Double { goal > 0 ? min(totalCalories / goal, 1) : 0 }
    private var remaining: Int { Int(goal - totalCalories) }
    private var isOver: Bool { totalCalories > goal }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Calories")
                    .font(.system(size: 16, weight: .bold)).foregroundColor(.ncPrimary)
                Spacer()
                Text(isOver ? "\(-remaining) over" : "\(remaining) left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isOver ? .ncOrange : .ncIndigo)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(isOver ? Color.ncOrangeLight : Color.ncIndigoLight, in: Capsule())
            }

            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(Color.ncSurfaceContHigh, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: 0.75 * progress)
                    .stroke(isOver ? Color.ncOrange : Color.ncPrimary, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(135))
                    .animation(.smooth(duration: 0.7), value: progress)

                VStack(spacing: 2) {
                    Text("\(Int(totalCalories))")
                        .font(.system(size: 44, weight: .bold).monospacedDigit())
                        .tracking(-1)
                        .foregroundColor(.ncPrimary)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: Int(totalCalories))
                    Text("of \(Int(goal)) kcal")
                        .font(.system(size: 13)).foregroundColor(.ncSecondary)
                }
            }
            .frame(width: 210, height: 210)
            .frame(height: 175, alignment: .top)

            HStack(spacing: 8) {
                MacroStat(color: .ncPrimary, title: "Protein", value: protein, target: proteinGoal)
                MacroStat(color: .ncOrange, title: "Fat", value: fat, target: fatGoal)
                MacroStat(color: .ncGreen, title: "Carbs", value: carbs, target: carbGoal)
            }
        }
        .padding(20)
        .glassCard()
    }
}

private struct MacroStat: View {
    let color: Color
    let title: String
    let value: Double
    let target: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 12, weight: .medium)).foregroundColor(.ncSecondary)
            }
            Text("\(Int(value))g")
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundColor(.ncPrimary)
                .contentTransition(.numericText())
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(color).frame(width: geo.size.width * min(max(target > 0 ? value / target : 0, 0), 1))
                }
            }
            .frame(height: 4)
            Text("/ \(Int(target))g").font(.system(size: 11)).foregroundColor(.ncSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ncSurfaceContLow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.smooth(duration: 0.5), value: value)
    }
}

// MARK: - Hydration & Minerals
struct LightHydrationCard: View {
    let hydration: DailyHydration
    let onAddWater: () -> Void
    let onAddSalt: () -> Void
    private var waterLiters: Double { hydration.waterOunces * 0.0295735 }
    private var saltGrams: Double { hydration.addedSodiumMg / 1000.0 }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Hydration & Minerals")
                    .font(.system(size: 16, weight: .bold)).foregroundColor(.ncPrimary)
                Spacer()
                Text("\(Int(min(waterLiters / 3.5, 1) * 100))% of water goal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ncGreen)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.ncGreenLight).cornerRadius(12)
            }

            HStack(spacing: 12) {
                HydrationTile(icon: "drop.fill", tint: .ncSky, tintBg: .ncSkyLight,
                              value: String(format: "%.1fL", waterLiters), target: "Target 3.5L",
                              progress: waterLiters / 3.5, buttonTitle: "+250ml", action: onAddWater)
                HydrationTile(icon: "sparkles", tint: .ncGreen, tintBg: .ncGreenLight,
                              value: String(format: "%.1fg", saltGrams), target: "Target 5.0g",
                              progress: saltGrams / 5.0, buttonTitle: "+Salt", action: onAddSalt)
            }
        }
        .padding(20)
        .glassCard()
    }
}

private struct HydrationTile: View {
    let icon: String
    let tint: Color
    let tintBg: Color
    let value: String
    let target: String
    let progress: Double
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon).font(.system(size: 18)).foregroundColor(tint)
                Spacer()
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tint)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(tint.opacity(0.15), in: Capsule())
                }
                .smoothButton()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundColor(.ncPrimary)
                    .contentTransition(.numericText())
                Text(target).font(.system(size: 11)).foregroundColor(.ncSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(tint).frame(width: geo.size.width * min(max(progress, 0), 1))
                }
            }
            .frame(height: 5)
            .animation(.smooth(duration: 0.5), value: progress)
        }
        .padding(14)
        .background(tintBg.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Meal Log (Light)
struct LightMealLogSection: View {
    let meals: [MealEntry]
    let onDelete: (MealEntry) -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Text("Today's Meals")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.ncPrimary)
                }
                Spacer()
                Text("\(meals.count) logged")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.ncSecondary)
            }
            
            VStack(spacing: 10) {
                if meals.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "fork.knife").font(.system(size: 22, weight: .light)).foregroundColor(.ncOutline)
                        Text("No meals logged today")
                            .font(.system(size: 14)).foregroundColor(.ncSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .glassCard()
                } else {
                    ForEach(meals.reversed()) { meal in
                        LightMealRow(meal: meal) { onDelete(meal) }
                            .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity),
                                                    removal: .opacity.combined(with: .move(edge: .leading))))
                    }
                }
            }
        }
    }
}

struct LightMealRow: View {
    let meal: MealEntry
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0
    
    private var timeStr: String {
        let f = DateFormatter(); f.timeStyle = .short; return f.string(from: meal.date)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < -20 {
                Button(action: { onDelete(); offset = 0 }) {
                    Text("Delete")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .frame(maxHeight: .infinity)
                        .background(Color.ncError)
                }
                .cornerRadius(16)
            }
            
            HStack(spacing: 14) {
                // Image placeholder (light gray rounded box)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.ncSurfaceContHigh)
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: "fork.knife").foregroundColor(.ncOutline))
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(meal.foodName.capitalized)
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.ncPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(meal.calories)) kcal")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.ncPrimary)
                    }
                    
                    HStack(spacing: 8) {
                        if !meal.source.isEmpty {
                            Text(meal.source)
                                .font(.system(size: 10, weight: .semibold)).foregroundColor(.ncGreen)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.ncGreenLight)
                                .cornerRadius(4)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.ncGreen.opacity(0.3), lineWidth: 1))
                        }
                        Text(timeStr)
                            .font(.system(size: 11)).foregroundColor(.ncSecondary)
                    }
                    .padding(.top, 2)
                    
                    HStack(spacing: 10) {
                        Text("P: \(Int(meal.protein))g")
                        Text("•")
                        Text("F: \(Int(meal.totalFat))g")
                        Text("•")
                        Text("C: \(Int(meal.carbohydrates))g")
                    }
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.ncSecondary)
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .background(Color.ncSurfaceContLowest)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { if $0.translation.width < 0 { offset = $0.translation.width } }
                    .onEnded { value in
                        withAnimation(.spring()) { offset = value.translation.width < -50 ? -90 : 0 }
                    }
            )
        }
    }
}
