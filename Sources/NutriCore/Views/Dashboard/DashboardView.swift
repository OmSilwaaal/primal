import SwiftUI
import SwiftData
import WidgetKit

// MARK: - Home
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @Query private var hydrations: [DailyHydration]
    @Query private var sunSessions: [SunSession]
    @AppStorage(RawSettings.sunGoalKey) private var sunGoal = 30
    /// Apple Watch "time in daylight" per day, from Health.
    @State private var daylight: [Date: Double] = [:]
    @StateObject private var healthManager = HealthKitManager.shared

    var onSearch: () -> Void = {}
    var onOpenProfile: () -> Void = {}
    @State private var pushed: SecondaryScreen?
    @State private var showWater = false
    /// The day Home shows. Past days are view-only.
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @AppStorage(HealthPrimingView.pendingKey) private var healthPrimingPending = false

    init(onSearch: @escaping () -> Void = {}, onOpenProfile: @escaping () -> Void = {}) {
        self.onSearch = onSearch
        self.onOpenProfile = onOpenProfile
        // Rows back to the start of the month (eating cycle) or the date wheel's history, whichever is earlier.
        // Days are filtered in memory so the view survives midnight.
        let cal = Calendar.current, today = cal.startOfDay(for: .now)
        let month = cal.dateInterval(of: .month, for: today)?.start ?? today
        let history = cal.date(byAdding: .day, value: -(EatingCycle.historyDays - 1), to: today) ?? today
        let cutoff = min(month, history)
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= cutoff }, sort: \.date)
        _hydrations = Query(filter: #Predicate<DailyHydration> { $0.date >= cutoff }, sort: \.date)
        _sunSessions = Query(filter: #Predicate<SunSession> { $0.start >= cutoff }, sort: \.start)
    }

    private var baseGoals: NutrientGoals { profiles.first.map(NutrientGoals.from) ?? .default }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }
    /// Active energy from Apple Health is only fetched for today, so past days use the base target.
    private var goals: NutrientGoals {
        var g = baseGoals
        if isToday, profiles.first != nil, healthManager.todayActiveEnergy > 0 { g.calories += healthManager.todayActiveEnergy }
        return g
    }
    private var dayMeals: [MealEntry] {
        let cal = Calendar.current; return meals.filter { cal.isDate($0.date, inSameDayAs: selectedDay) }
    }
    /// Minutes outside: manual sessions or Apple Watch daylight, whichever is larger (they can overlap).
    private var daySunMinutes: Double {
        let cal = Calendar.current
        let manual = sunSessions.filter { cal.isDate($0.start, inSameDayAs: selectedDay) }.reduce(0) { $0 + $1.minutes }
        return max(manual, daylight[cal.startOfDay(for: selectedDay)] ?? 0)
    }
    private var dayHydration: DailyHydration? {
        hydrations.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) })
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

    private var drinksMl: Double { (dayHydration?.waterOunces ?? 0) * WaterSheet.mlPerOunce }
    private var foodWaterMl: Double { FoodWater.millilitres(in: dayMeals) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Bento.gap) {
                    BentoHomeHeader(day: selectedDay, onToday: isToday ? nil : { select(Calendar.current.startOfDay(for: .now)) },
                                    onProfile: onOpenProfile) {
                        DaySummaryCard(day: selectedDay, calories: dayMeals.totalCalories, goal: goals.calories,
                                       protein: dayMeals.totalProtein, carbs: dayMeals.totalCarbs, fat: dayMeals.totalFat,
                                       waterLitres: (drinksMl + foodWaterMl) / 1000, sunMinutes: daySunMinutes)
                    }
                    .padding(.top, 8)

                    // Past days: scroll the drum back; the tiles below follow the day it lands on (view-only).
                    DateWheel(days: EatingCycle(meals: meals, calorieGoal: baseGoals.calories).history,
                              selected: selectedDay, onSelect: select)
                        .padding(.horizontal, -Bento.margin)

                    CalorieTile(total: dayMeals.totalCalories, goal: goals.calories, isToday: isToday, macros: [
                        ("Protein", dayMeals.totalProtein, goals.protein),
                        ("Carbs", dayMeals.totalCarbs, goals.carbohydrates),
                        ("Fat", dayMeals.totalFat, goals.fat),
                    ])

                    BentoPair {
                        Button { showWater = true } label: {
                            BentoTile(title: "Water", value: String(format: "%.1f", (drinksMl + foodWaterMl) / 1000),
                                      detail: "of \(String(format: "%.1f", WaterSheet.goalMl / 1000)) L",
                                      progress: (drinksMl + foodWaterMl) / WaterSheet.goalMl, symbol: "drop",
                                      art: .water, artPlacement: .band)
                                // The add cue, top right; the whole tile is the button.
                                .overlay(alignment: .topTrailing) {
                                    if isToday {
                                        Image(systemName: "plus")
                                            .font(.ui(size: 13, weight: .bold)).foregroundColor(Mono.text)
                                            .frame(width: 28, height: 28)
                                            .glass(.clear, in: Circle(), interactive: true)
                                            .padding(10)
                                            .accessibilityHidden(true)
                                    }
                                }
                        }
                        .buttonStyle(PressScaleStyle())
                        .disabled(!isToday)
                        .accessibilityHint(isToday ? "Adds water" : "")
                    } right: {
                        Button { pushed = .sun } label: {
                            BentoTile(title: "Sun", value: "\(Int(daySunMinutes))", detail: "of \(sunGoal) min",
                                      progress: sunGoal > 0 ? daySunMinutes / Double(sunGoal) : 0, symbol: "sun.max", art: .sun)
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityHint("Opens Sun")
                    }

                    MealsTile(meals: dayMeals, readOnly: !isToday, onAdd: onSearch) { meal in
                        Haptics.success()
                        let name = meal.foodName.components(separatedBy: ",").first ?? meal.foodName
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { MealLogger.delete(meal, in: modelContext) }
                        ToastCenter.shared.show("Removed — \(name)")
                    }
                    // Each day's list fades in rather than snapping when the date changes.
                    .id(selectedDay)
                    .transition(.opacity.combined(with: .offset(y: 10)))
                }
                .padding(.horizontal, Bento.margin)
                .padding(.bottom, 120)
            }
            .glassLightFollowsScroll()
            .sharedBackdropRoot()
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("Home") // names the back button on pushed screens
            .navigationDestination(item: $pushed) { $0.destination }
            .sheet(isPresented: $showWater) {
                WaterSheet(drinksMl: drinksMl, foodMl: foodWaterMl) { ml in
                    guard let hydration = todaysHydration else { return }
                    let ounces = ml / WaterSheet.mlPerOunce
                    withAnimation(.smooth(duration: 0.45)) { hydration.waterOunces += ounces }
                    try? modelContext.save()
                    healthManager.saveDietaryWater(ounces: ounces)
                    Haptics.success()
                    ToastCenter.shared.show("Added \(Int(ml)) ml water", branded: true)
                }
            }
            // Offered once after profile setup, explaining what's read and written before the system prompt.
            .sheet(isPresented: $healthPrimingPending) {
                HealthPrimingView { healthPrimingPending = false }
                    .presentationDetents([.large])
                    .presentationBackground(Color.ncBg)
            }
            .task {
                ensureRecords()
                await healthManager.fetchTodayData()
                daylight = await healthManager.dailyDaylightMinutes(days: EatingCycle.historyDays)
                publishSnapshot()
                await SocialService.shared.backfill(meals)
            }
            .onChange(of: todaySnapshot) { _, _ in publishSnapshot() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    ensureRecords()
                    Task { await healthManager.fetchTodayData() }
                }
            }
        }
    }

    /// Today's numbers for the widgets, whatever day Home is showing.
    private var todaySnapshot: WidgetSnapshot {
        let cal = Calendar.current
        var calorieGoal = baseGoals.calories
        if profiles.first != nil, healthManager.todayActiveEnergy > 0 { calorieGoal += healthManager.todayActiveEnergy }
        let drinksMl = (todaysHydration?.waterOunces ?? 0) * WaterSheet.mlPerOunce
        let manualSun = sunSessions.filter { cal.isDateInToday($0.start) }.reduce(0) { $0 + $1.minutes }
        return WidgetSnapshot(day: cal.startOfDay(for: .now), calories: todaysMeals.totalCalories, calorieGoal: calorieGoal,
                              waterLitres: (drinksMl + FoodWater.millilitres(in: todaysMeals)) / 1000, waterGoalLitres: WaterSheet.goalMl / 1000,
                              sunMinutes: max(manualSun, daylight[cal.startOfDay(for: .now)] ?? 0),
                              sunGoalMinutes: Double(sunGoal))
    }

    private func publishSnapshot() {
        if todaySnapshot.save() { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Moves Home to another day; every section follows with the same smooth animation.
    private func select(_ day: Date) {
        let day = Calendar.current.startOfDay(for: day)
        guard day != selectedDay else { return }
        withAnimation(.smooth(duration: 0.45)) { selectedDay = day }
    }
}

// MARK: - Eating cycle
/// The cycle is the calendar month: one tick per day, past days marked by whether intake landed within
/// 85–110% of the calorie goal. Days with nothing logged stay neutral.
struct EatingCycle {
    enum Mark { case onTarget, offTarget, today, upcoming, empty }
    struct Day: Identifiable, Equatable { let id: Date; let mark: Mark; let weekday: String; let number: Int }

    /// How far back the date wheel goes.
    static let historyDays = 30

    let day: Int
    let length: Int
    /// One per day of the calendar month, with its date.
    let ticks: [(date: Date, mark: Mark)]
    /// The last `historyDays` days, oldest first, ending today.
    let history: [Day]

    init(meals: [MealEntry], calorieGoal: Double, now: Date = .now) {
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
        ticks = (0..<length).map { i in
            let d = cal.date(byAdding: .day, value: i, to: month.start)!
            return (d, mark(d))
        }

        let f = DateFormatter(); f.dateFormat = "EEE"
        history = (0..<Self.historyDays).reversed().map { back in
            let d = cal.date(byAdding: .day, value: -back, to: today)!
            return Day(id: d, mark: mark(d), weekday: f.string(from: d).uppercased(), number: cal.component(.day, from: d))
        }
    }
}

extension EatingCycle.Mark {
    /// How VoiceOver describes a day on the wheel.
    var spoken: String {
        switch self {
        case .onTarget: "on target"
        case .offTarget: "under or over target"
        case .today: "today"
        case .upcoming: "upcoming"
        case .empty: "nothing logged"
        }
    }
}

// MARK: - Header

/// "Sunday, Nov 1" over the big title (Today, Yesterday or the weekday), with round glass Share and Profile buttons.
/// A "Today" capsule appears on past days. One fixed row, so nothing below jumps when it appears.
private struct BentoHomeHeader<Card: View>: View {
    let day: Date
    /// Set when a past day is showing.
    let onToday: (() -> Void)?
    let onProfile: () -> Void
    @ViewBuilder let shareCard: () -> Card

    private var label: String { day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }
    private var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.bentoBody).foregroundColor(Mono.label).lineLimit(1)
                Text(title).font(.bentoTitle).foregroundColor(Mono.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                if let onToday {
                    Button("Today", action: onToday)
                        .buttonStyle(BentoCapsuleButtonStyle(solid: false, height: 44))
                        .fixedSize()
                        .accessibilityHint("Shows today")
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                ShareCardButton(title: "Share day", round: true, card: shareCard)
                Button(action: onProfile) { Image(systemName: "person") }
                    .buttonStyle(.bentoRound)
                    .accessibilityLabel("Profile")
            }
            }
            // Interactive glass reacts ~24 pt beyond its edge and would catch drags meant for the date wheel below.
            .environment(\.glassInteractive, false)
            .fixedSize()
        }
        .frame(minHeight: 64)
    }
}

// MARK: - Date wheel

/// The last 30 days as pills on a drum: scroll back through past days and the one that snaps to the centre is the
/// day Home shows. Tapping a pill spins it there. Today sits at the right end. Each pill's dot tells the day by shape:
/// filled on target, a ring under or over, faint with nothing logged.
private struct DateWheel: View {
    let days: [EatingCycle.Day]
    let selected: Date
    let onSelect: (Date) -> Void
    @State private var centered: Date?

    private let pillWidth: CGFloat = 50

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let centerX = geo.frame(in: .global).midX
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days) { day in
                        pill(day)
                            .drumEffect(centerX: centerX, radius: width * 0.36)
                    }
                }
                .scrollTargetLayout()
            }
            // Room on both sides so the first and last pills can reach the centre.
            .safeAreaPadding(.horizontal, max(0, (geo.size.width - pillWidth) / 2))
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centered, anchor: .center)
            .scrollClipDisabled()
            .drumRimFade()
        }
        .frame(height: 88)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onAppear { centered = selected }
        .onChange(of: centered) { _, new in
            guard let new, new != selected else { return }
            Haptics.selection()
            onSelect(new)
        }
        .onChange(of: selected) { _, new in
            if centered != new { withAnimation(.smooth(duration: 0.45)) { centered = new } }
        }
    }

    private func pill(_ day: EatingCycle.Day) -> some View {
        let on = day.id == selected
        return Button {
            withAnimation(.smooth(duration: 0.45)) { centered = day.id }
        } label: {
            VStack(spacing: 6) {
                Text(day.weekday.capitalized).font(.ui(size: 12, weight: .medium)).opacity(0.8)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("\(day.number)").font(.bentoNumber(18)).tracking(Font.bentoTracking(18))
                    .lineLimit(1).minimumScaleFactor(0.6)
                markDot(day.mark, on: on).frame(width: 6, height: 6)
            }
            .foregroundColor(on ? Mono.onWhite : Mono.text)
            .frame(width: pillWidth)
            .padding(.top, 10).padding(.bottom, 9)
            .background {
                // Drawn see-through glass, not system Liquid Glass: system glass morphs under the drum's 3D turn.
                if on {
                    Capsule().fill(Mono.text)
                } else {
                    Capsule().fill(Color.clear).liquidGlassPanel(in: Capsule())
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.3), value: on)
        .accessibilityLabel("\(day.id.formatted(.dateTime.weekday(.wide).month(.wide).day())), \(day.mark.spoken)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func markDot(_ m: EatingCycle.Mark, on: Bool) -> some View {
        let ink = on ? Mono.onWhite : Mono.text
        switch m {
        case .onTarget, .today: Circle().fill(ink)
        case .offTarget: Circle().strokeBorder(ink, lineWidth: 1.5)
        case .upcoming, .empty: Circle().fill(ink.opacity(0.25))
        }
    }
}

// MARK: - Calories

/// The centrepiece: a large ring with the app's rune, the day's kcal and what's left (or how far under/over on a past
/// day) inside, then the three macros side by side, each with its bar. The rune lights up once the target is hit.
private struct CalorieTile: View {
    let total: Double
    let goal: Double
    let isToday: Bool
    let macros: [(String, Double, Double)]

    private let ringSize: CGFloat = 240
    private let ringWidth: CGFloat = 26

    private var progress: Double { goal > 0 ? total / goal : 0 }
    private var reached: Bool { progress >= 1 }
    private var remaining: (value: String, word: String) {
        let diff = Int((goal - total).rounded())
        if isToday { return (max(0, diff).formatted(), "left") }
        return diff >= 0 ? (diff.formatted(), "under") : ((-diff).formatted(), "over")
    }

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                GlassRing(width: ringWidth)
                Circle()
                    .trim(from: 0, to: min(progress, 1))
                    .stroke(Mono.text, style: StrokeStyle(lineWidth: ringWidth - 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(ringWidth / 2)   // same centre line as the glass tube
                    .animation(.smooth(duration: 0.6), value: progress)
                VStack(spacing: 2) {
                    AlgizMark().fill(Mono.text.opacity(reached ? 1 : 0.45))
                        .frame(width: 14, height: 18)
                        .padding(.bottom, 6)
                        .animation(.smooth(duration: 0.4), value: reached)
                    Text(Int(total).formatted()).font(.bentoNumber(56)).tracking(Font.bentoTracking(56))
                        .foregroundColor(Mono.text)
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: Int(total))
                    Text("kcal").font(.ui(size: 14, weight: .medium)).foregroundColor(Mono.label)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(remaining.value).font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
                            .contentTransition(.numericText())
                        Text("\(remaining.word) of \(Int(goal).formatted())").font(.ui(size: 13)).foregroundColor(Mono.label)
                    }
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 8)
                }
                .padding(.horizontal, ringWidth + 18)
            }
            .frame(width: ringSize, height: ringSize)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Calories")
            .accessibilityValue("\(Int(total)) of \(Int(goal)) kcal, \(remaining.value) \(remaining.word)")

            HStack(alignment: .top, spacing: 14) {
                ForEach(macros, id: \.0) { name, cur, target in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(name).font(.ui(size: 13, weight: .medium)).foregroundColor(Mono.label)
                        (Text("\(Int(cur.rounded()))").foregroundColor(Mono.text)
                         + Text(" / \(Int(target.rounded())) g").foregroundColor(Mono.label))
                            .font(.ui(size: 13, weight: .semibold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.7)
                        BentoBar(value: target > 0 ? cur / target : 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .onChange(of: reached) { was, now in
            // Celebrate crossing the line today, once per day; not on opening the app already past it.
            guard isToday, !was, now else { return }
            let key = "targetHitDay", day = Date.now.formatted(.iso8601.year().month().day())
            guard UserDefaults.standard.string(forKey: key) != day else { return }
            UserDefaults.standard.set(day, forKey: key)
            Haptics.success()
            ToastCenter.shared.show("Target hit", branded: true)
        }
    }
}

// MARK: - Glass ring

/// The ring's track as a tube of the clearest Liquid Glass in the app: system .clear glass with no tint (iOS 26),
/// hairline inner and outer edges so the tube reads, and the moving light along it. Before iOS 26 it's a barely
/// there film with the same edges; Reduce Transparency and Increase Contrast get a solid track.
private struct GlassRing: View {
    let width: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let ring = RingShape(width: width)
        if reduceTransparency || contrast == .increased {
            ring.fill(Color.white.opacity(contrast == .increased ? 0.3 : 0.18))
        } else {
            Group {
                if #available(iOS 26.0, *) {
                    Color.clear.glassEffect(.clear, in: ring)
                } else {
                    ring.fill(Color.white.opacity(0.03))
                }
            }
            .overlay(ring.stroke(Color.white.opacity(0.22), lineWidth: 0.8))
            .overlay(GlassSheen(shape: ring, strength: 1.1))
            .allowsHitTesting(false)
        }
    }
}

/// A ring `width` wide, centred on the circle that fits the rect inset by half the width (the same circle a stroke
/// of that width would follow).
private struct RingShape: Shape {
    let width: CGFloat
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let circle = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
            .insetBy(dx: width / 2, dy: width / 2)
        return Path(ellipseIn: circle).strokedPath(StrokeStyle(lineWidth: width))
    }
}

// MARK: - Water

/// Adding water, from the Water tile: pick an amount on the wheel and add it. Water only goes up; food water counts
/// toward the total automatically.
struct WaterSheet: View {
    static let mlPerOunce = 29.5735
    static let goalMl = 3500.0
    private static let amounts: [Double] = [150, 250, 330, 500, 750, 1000]

    let drinksMl: Double
    let foodMl: Double
    let onAdd: (Double) -> Void
    @State private var amount = 250.0
    @Environment(\.dismiss) private var dismiss

    private func litres(_ ml: Double) -> String { String(format: "%.1f", ml / 1000) }
    private func label(_ ml: Double) -> String { ml >= 1000 ? "1 L" : "\(Int(ml)) ml" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add water").font(.ui(size: 22, weight: .bold)).foregroundColor(Mono.text)
                Text("\(litres(drinksMl + foodMl)) of \(litres(Self.goalMl)) L today · \(litres(foodMl)) L from food")
                    .font(.bentoBody).foregroundColor(Mono.label)
            }
            ArcWheel(items: Self.amounts, selection: $amount, onTapSelected: add) { ml, on in
                Text(label(ml))
                    .font(.ui(size: 15, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundColor(on ? Mono.onWhite : Mono.text)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background {
                        if on { Capsule().fill(Mono.text) } else { Capsule().fill(Color.clear).liquidGlassPanel(in: Capsule()) }
                    }
                    .contentShape(Capsule())
                    .animation(.smooth(duration: 0.25), value: on)
            }
            .accessibilityRepresentation {
                Picker("Amount", selection: $amount) {
                    ForEach(Self.amounts, id: \.self) { Text(label($0)).tag($0) }
                }
            }
            Button("Add \(label(amount))", action: add).buttonStyle(.bentoPrimary)
        }
        .padding(20)
        .presentationDetents([.height(320)])
        .glassSheetBackground()
        .presentationCornerRadius(Bento.radius)
    }

    private func add() {
        onAdd(amount)
        dismiss()
    }
}

// MARK: - Meals

/// The day's meals, newest first: meal (by time of day), food, kcal. Long-press to remove (confirmed first, since it
/// also leaves Apple Health and friends' feeds). Past days are view-only.
private struct MealsTile: View {
    let meals: [MealEntry]
    let readOnly: Bool
    let onAdd: () -> Void
    let onDelete: (MealEntry) -> Void
    @State private var pendingDelete: MealEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(meals.isEmpty ? "Meals" : "Meals · \(meals.count)").font(.bentoLabel).foregroundColor(Mono.label)
                Spacer()
                if !readOnly {
                    Button(action: onAdd) { Label("Add", systemImage: "plus").padding(.horizontal, 4) }
                        .buttonStyle(BentoCapsuleButtonStyle(solid: false, height: 36))
                        .fixedSize()
                        .accessibilityLabel("Log food")
                }
            }
            .padding(.bottom, 4)

            if meals.isEmpty {
                Text(readOnly ? "Nothing logged this day" : "Nothing logged yet. Add a meal or scan one.")
                    .font(.bentoBody).foregroundColor(Mono.label)
                    .padding(.vertical, 14)
            } else {
                ForEach(Array(meals.reversed().enumerated()), id: \.element.id) { i, meal in
                    row(meal)
                        .overlay(alignment: .top) {
                            if i > 0 { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
                        }
                        .contextMenu {
                            if !readOnly {
                                Button(role: .destructive) { pendingDelete = meal } label: { Label("Remove", systemImage: "trash") }
                            }
                        }
                }
            }
        }
        .bentoTile(art: .meat)
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

    private func row(_ meal: MealEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MealSlot.name(for: meal.date)).font(.ui(size: 12, weight: .medium)).foregroundColor(Mono.label)
                Text(meal.foodName.components(separatedBy: ",").first?.capitalized ?? meal.foodName)
                    .font(.bentoBody).foregroundColor(Mono.text).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Int(meal.calories).formatted()).font(.ui(size: 17, weight: .semibold)).foregroundColor(Mono.text)
                Text("kcal").font(.ui(size: 12)).foregroundColor(Mono.label)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(readOnly ? "" : "Touch and hold to remove")
    }
}
