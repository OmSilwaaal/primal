import SwiftUI
import SwiftData

// MARK: - Dashboard (pixel-matched from "Autonomous Metabolic Intelligence" Light Theme)
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @Query private var fastingStates: [FastingState]
    @Query private var hydrations: [DailyHydration]
    @StateObject private var healthManager = HealthKitManager.shared

    var onScan: () -> Void = {}
    var onProfile: () -> Void = {}

    init(onScan: @escaping () -> Void = {}, onProfile: @escaping () -> Void = {}) {
        self.onScan = onScan
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

    /// Creates the singleton fasting row and today's hydration row if they don't exist yet.
    private func ensureRecords() {
        if fastingStates.isEmpty { modelContext.insert(FastingState()) }
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
                            .padding(.top, 56)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)

                        // ── Daily Insight ──────────────────────────────
                        DailyInsightCard(
                            calories: todaysMeals.totalCalories, calorieGoal: goals.calories,
                            protein: todaysMeals.totalProtein, proteinGoal: goals.protein,
                            mealCount: todaysMeals.count, fasting: fastingStates.first
                        )
                        .padding(.horizontal, 16)

                        // ── Fasting Clock ───────────────────────────────────
                        if let fasting = fastingStates.first {
                            LightFastingCard(state: fasting) {
                                if fasting.isFasting {
                                    fasting.isFasting = false
                                    fasting.startTime = nil
                                } else {
                                    fasting.isFasting = true
                                    fasting.startTime = Date()
                                }
                                try? modelContext.save()
                            } onExtendTarget: {
                                fasting.targetDurationHours = min(fasting.targetDurationHours + 1, 48)
                                try? modelContext.save()
                            }
                            .padding(.horizontal, 16)
                        }

                        // ── Metabolic Budget ─────────────────────────────
                        LightMetabolicBudgetCard(
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
                            withAnimation(.spring()) { modelContext.delete(meal) }
                        }
                        .padding(.horizontal, 16)

                        Spacer().frame(height: 160)
                    }
                }

                // Floating Action Button
                VStack {
                    Spacer()
                    Button(action: onScan) {
                        HStack(spacing: 10) {
                            Image(systemName: "camera.macro")
                                .font(.system(size: 20))
                                .foregroundColor(Color(hex: "#c7d2fe"))
                            Text("Scan or Log Metabolic Fuel")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "sparkles")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "#fed7aa"))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.ncPrimary)
                        .cornerRadius(26)
                        .shadow(color: Color.black.opacity(0.15), radius: 10, y: 4)
                        .padding(.horizontal, 24)
                    }
                    .smoothButton()
                    .padding(.bottom, 90) // Above tab bar
                }
            }
            .navigationBarHidden(true)
            .task {
                ensureRecords()
                await healthManager.fetchTodayData()
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
                        Image(systemName: "person.fill").font(.system(size: 14)).foregroundColor(.white)
                    }
                }
            }
        }
    }
}

// MARK: - Daily Insight Card (derived from logged data, no AI involved)
struct DailyInsightCard: View {
    let calories: Double
    let calorieGoal: Double
    let protein: Double
    let proteinGoal: Double
    let mealCount: Int
    let fasting: FastingState?

    private var fastEnd: Date? {
        guard let f = fasting, f.isFasting, let start = f.startTime else { return nil }
        return start.addingTimeInterval(f.targetDurationHours * 3600)
    }

    private var headline: String {
        if let end = fastEnd {
            return end > Date() ? "Fast in progress" : "Fast target reached"
        }
        if mealCount == 0 { return "Nothing logged yet" }
        let left = Int(calorieGoal - calories)
        return left > 0 ? "\(left) kcal left today" : "Calorie goal reached"
    }

    private var detail: Text {
        if let end = fastEnd {
            return end > Date()
                ? Text("Your eating window opens at ") + Text(end, style: .time).fontWeight(.semibold).foregroundColor(.ncPrimary) + Text(".")
                : Text("You can break your fast whenever you're ready.")
        }
        if mealCount == 0 { return Text("Scan a barcode, snap a photo, or search to log your first meal.") }
        let toGo = Int(proteinGoal - protein)
        return toGo > 0 ? Text("\(toGo)g of protein to go to hit today's target.") : Text("Protein target met.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TODAY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.ncIndigo)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.ncIndigoLight)
                    .cornerRadius(12)
                Spacer()
                if calorieGoal > 0 {
                    Text("\(Int(calories / calorieGoal * 100))% of goal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.ncGreen)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.ncGreenLight)
                        .cornerRadius(12)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.ncPrimary)
                detail
                    .font(.ncBodySm)
                    .foregroundColor(.ncSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .glassCard()
    }
}

// MARK: - Fasting Clock (Light)
struct LightFastingCard: View {
    let state: FastingState
    let onToggle: () -> Void
    let onExtendTarget: () -> Void
    private var targetSeconds: Double { state.targetDurationHours * 3600.0 }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(Color.ncIndigo).frame(width: 8, height: 8)
                    Text("FASTING CLOCK")
                        .font(.ncLabelMonoBold).tracking(1).foregroundColor(.ncPrimary)
                }
                Spacer()
                if let start = state.startTime {
                    Text("Started \(start, style: .time)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.ncSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 2)
                        .background(Color.ncSurface)
                        .cornerRadius(12)
                }
            }
            
            // Circular Arc Progress
            TimelineView(.periodic(from: .now, by: 1.0)) { ctx in
                let elapsed = state.isFasting && state.startTime != nil ? ctx.date.timeIntervalSince(state.startTime!) : 0
                let pct = state.isFasting ? min(elapsed / targetSeconds, 1.0) : 0
                
                let h = Int(elapsed) / 3600
                let m = (Int(elapsed) % 3600) / 60
                
                ZStack {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(Color.ncSurface, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .frame(width: 200, height: 200)
                    
                    Circle()
                        .trim(from: 0, to: 0.75 * pct)
                        .stroke(Color.ncIndigo, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .frame(width: 200, height: 200)
                        .animation(.linear(duration: 1.0), value: pct)
                    
                    VStack(spacing: 4) {
                        Text("Autophagy Stage")
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1).foregroundColor(.ncSecondary)
                            .textCase(.uppercase)
                        Text(String(format: "%02dh %02dm", h, m))
                            .font(.system(size: 36, weight: .bold))
                            .tracking(-1).foregroundColor(.ncPrimary)
                        Text("Target \(Int(state.targetDurationHours))h (\(Int(pct * 100))%)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.ncIndigo)
                    }
                }
            }
            .frame(height: 180)
            
            // Stage indicators (estimated from time fasted)
            TimelineView(.periodic(from: .now, by: 60.0)) { ctx in
                let hours = state.isFasting && state.startTime != nil ? ctx.date.timeIntervalSince(state.startTime!) / 3600 : 0
                HStack(spacing: 8) {
                    StagePill(label: "Glycogen", status: hours >= 12 ? "Depleted" : (hours > 0 ? "Burning" : "—"), isComplete: hours >= 12)
                    StagePill(label: "Ketosis", status: hours >= 14 ? "Active" : "Pending", isComplete: hours >= 14)
                    StagePill(label: "Autophagy", status: hours >= 16 ? "Active" : "Pending", isComplete: hours >= 16, highlight: hours >= 16)
                }
            }
            
            // Buttons
            HStack(spacing: 10) {
                Button(action: onExtendTarget) {
                    Text("+1h Target")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.ncPrimary)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Color.ncSurface)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.05), lineWidth: 1))
                }.smoothButton()
                
                Button(action: onToggle) {
                    Text(state.isFasting ? "End Fast" : "Start Fast")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Color.ncPrimary)
                        .cornerRadius(12)
                }.smoothButton()
            }
        }
        .padding(20)
        .glassCard()
    }
}

struct StagePill: View {
    let label: String
    let status: String
    let isComplete: Bool
    var highlight: Bool = false
    
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 10, weight: .medium)).tracking(1).textCase(.uppercase)
                .foregroundColor(highlight ? .ncIndigo : .ncSecondary)
            Text(status).font(.system(size: 12, weight: .semibold))
                .foregroundColor(highlight ? .ncIndigo : .ncPrimary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(highlight ? Color.ncIndigoLight : Color.ncSurface)
        .cornerRadius(12)
    }
}

// MARK: - Metabolic Budget (Light)
struct LightMetabolicBudgetCard: View {
    let totalCalories, goal, protein, proteinGoal, fat, fatGoal, carbs, carbGoal: Double
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY'S CALORIES")
                        .font(.ncLabelMonoBold).tracking(1).foregroundColor(.ncSecondary)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(Int(totalCalories))")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.ncPrimary)
                        Text("/ \(Int(goal)) kcal")
                            .font(.system(size: 13)).foregroundColor(.ncSecondary)
                    }
                }
                Spacer()
                Text("\(Int(max(0, goal - totalCalories))) kcal left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ncIndigo)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.ncIndigoLight)
                    .cornerRadius(12)
            }
            
            // Stacked Bar
            GeometryReader { geo in
                let w = geo.size.width
                // Segments are each macro's calories as a share of the calorie goal (4/9/4 kcal per gram),
                // scaled down together if the day goes over goal.
                let safeGoal = max(goal, 1)
                let raw = [protein * 4, fat * 9, carbs * 4].map { $0 / safeGoal }
                let squeeze = max(raw.reduce(0, +), 1)
                let pPct = raw[0] / squeeze
                let fPct = raw[1] / squeeze
                let cPct = raw[2] / squeeze

                HStack(spacing: 0) {
                    Rectangle().fill(Color.ncPrimary).frame(width: w * pPct)
                    Rectangle().fill(Color.ncOrange).frame(width: w * fPct)
                    Rectangle().fill(Color.ncGreen).frame(width: w * cPct)
                    Rectangle().fill(Color.ncSurface).frame(maxWidth: .infinity)
                }
                .cornerRadius(4)
            }
            .frame(height: 10)
            
            VStack(spacing: 8) {
                LightMacroRow(color: .ncPrimary, title: "Protein", subtitle: LightMacroRow.remaining(protein, proteinGoal), value: protein, target: proteinGoal)
                LightMacroRow(color: .ncOrange, title: "Fat", subtitle: LightMacroRow.remaining(fat, fatGoal), value: fat, target: fatGoal)
                LightMacroRow(color: .ncGreen, title: "Carbs", subtitle: LightMacroRow.remaining(carbs, carbGoal), value: carbs, target: carbGoal)
            }
        }
        .padding(20)
        .glassCard()
    }
}

struct LightMacroRow: View {
    let color: Color
    let title: String
    let subtitle: String
    let value: Double
    let target: Double

    static func remaining(_ value: Double, _ target: Double) -> String {
        let left = Int(target - value)
        return left > 0 ? "\(left)g left" : "\(-left)g over target"
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.ncPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundColor(.ncSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(value))g").font(.system(size: 13, weight: .bold)).foregroundColor(.ncPrimary)
                Text("/ \(Int(target))g").font(.system(size: 11)).foregroundColor(.ncSecondary)
            }
        }
        .padding(10)
        .background(Color.ncSurface.opacity(0.7))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.02), lineWidth: 1))
    }
}

// MARK: - Hydration & Minerals (Light)
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
                // Water
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "drop.fill").font(.system(size: 20)).foregroundColor(Color(hex: "#0284c7"))
                        Spacer()
                        Button(action: onAddWater) {
                            Text("+250ml")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#0369a1"))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.white).cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#bae6fd"), lineWidth: 1))
                        }.smoothButton()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1fL", waterLiters)).font(.system(size: 18, weight: .bold)).foregroundColor(Color(hex: "#0c4a6e"))
                        Text("Target: 3.5L").font(.system(size: 11)).foregroundColor(Color(hex: "#0284c7"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    GeometryReader { geo in
                        let pct = min(waterLiters / 3.5, 1.0)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.8))
                            Capsule().fill(Color(hex: "#38bdf8")).frame(width: geo.size.width * pct)
                                .animation(.spring(), value: pct)
                        }
                    }.frame(height: 6)
                }
                .padding(14).background(Color(hex: "#f0f9ff")).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#bae6fd").opacity(0.5), lineWidth: 1))
                
                // Salt
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles").font(.system(size: 20)).foregroundColor(Color.ncGreen)
                        Spacer()
                        Button(action: onAddSalt) {
                            Text("+Salt")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#047857"))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.white).cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#bbf7d0"), lineWidth: 1))
                        }.smoothButton()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.1fg", saltGrams)).font(.system(size: 18, weight: .bold)).foregroundColor(Color(hex: "#064e3b"))
                        Text("Target: 5.0g").font(.system(size: 11)).foregroundColor(Color.ncGreen)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    GeometryReader { geo in
                        let pct = min(saltGrams / 5.0, 1.0)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.8))
                            Capsule().fill(Color(hex: "#34d399")).frame(width: geo.size.width * pct)
                                .animation(.spring(), value: pct)
                        }
                    }.frame(height: 6)
                }
                .padding(14).background(Color(hex: "#f0fdf4")).cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#bbf7d0").opacity(0.5), lineWidth: 1))
            }
        }
        .padding(20)
        .glassCard()
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
                    Text("No meals logged today")
                        .font(.system(size: 14)).foregroundColor(.ncSecondary)
                        .padding(.vertical, 20)
                } else {
                    ForEach(meals.reversed()) { meal in
                        LightMealRow(meal: meal) { onDelete(meal) }
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
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .frame(maxHeight: .infinity)
                        .background(Color.ncError)
                }
                .cornerRadius(16)
            }
            
            HStack(spacing: 14) {
                // Image placeholder (light gray rounded box)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.ncSurface)
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: "photo").foregroundColor(.ncOutlineVariant))
                
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
            .background(Color.white)
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.05), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.03), radius: 4, y: 2)
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
