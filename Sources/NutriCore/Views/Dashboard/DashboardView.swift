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
    var onOpenData: () -> Void = {}
    @State private var showRawLog = false
    @State private var pushed: SecondaryScreen?
    /// The day Home shows. Past days are view-only.
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @AppStorage(HealthPrimingView.pendingKey) private var healthPrimingPending = false

    init(onSearch: @escaping () -> Void = {}, onOpenData: @escaping () -> Void = {}) {
        self.onSearch = onSearch
        self.onOpenData = onOpenData
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
    /// The day's vitamins and minerals against the base targets.
    private var dayMicros: [NutrientInfo] {
        buildNutrientList(from: dayMeals, goals: baseGoals).filter { $0.group != .macros }
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
                        HomeHeader(day: selectedDay, onToday: isToday ? nil : { select(Calendar.current.startOfDay(for: .now)) },
                                   onSearch: onSearch, onWeather: { pushed = .sun })
                            .padding(.horizontal, Space.margin)
                            .padding(.top, 12)

                        CycleSection(cycle: EatingCycle(meals: meals, calorieGoal: baseGoals.calories),
                                     selected: selectedDay, onSelect: select)
                            .padding(.top, 20)

                        CalorieRing(total: dayMeals.totalCalories, goal: goals.calories, isToday: isToday)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)

                        ShareCardButton(title: "Share day") {
                            DaySummaryCard(day: selectedDay, calories: dayMeals.totalCalories, goal: goals.calories,
                                           protein: dayMeals.totalProtein, carbs: dayMeals.totalCarbs, fat: dayMeals.totalFat,
                                           waterLitres: ((dayHydration?.waterOunces ?? 0) * HydrationSection.mlPerOunce
                                                         + FoodWater.millilitres(in: dayMeals)) / 1000,
                                           sunMinutes: daySunMinutes)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 16)

                        MacroGrid(items: [
                            ("Protein", dayMeals.totalProtein, goals.protein),
                            ("Carbs", dayMeals.totalCarbs, goals.carbohydrates),
                            ("Fat", dayMeals.totalFat, goals.fat),
                        ])

                        MicrosSunSection(micros: dayMicros, sunMinutes: daySunMinutes, sunGoal: Double(sunGoal),
                                         onMicros: isToday ? onOpenData : nil, onSun: { pushed = .sun })
                            .padding(.horizontal, Space.margin)
                            .padding(.top, 24)

                        MealsSection(meals: dayMeals, readOnly: !isToday, onAdd: onSearch) { meal in
                            Haptics.success()
                            let name = meal.foodName.components(separatedBy: ",").first ?? meal.foodName
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { MealLogger.delete(meal, in: modelContext) }
                            ToastCenter.shared.show("Removed — \(name)")
                        }
                        .padding(.top, 32)
                        // Each day's list fades in rather than snapping when the date changes.
                        .id(selectedDay)
                        .transition(.opacity.combined(with: .offset(y: 10)))

                        VStack(alignment: .leading, spacing: Space.section) {
                            HydrationSection(drinksMl: (dayHydration?.waterOunces ?? 0) * HydrationSection.mlPerOunce,
                                             foodMl: FoodWater.millilitres(in: dayMeals),
                                             readOnly: !isToday) { ml in
                                guard let hydration = todaysHydration else { return }
                                let ounces = ml / HydrationSection.mlPerOunce
                                withAnimation(.smooth(duration: 0.45)) { hydration.waterOunces += ounces }
                                try? modelContext.save()
                                healthManager.saveDietaryWater(ounces: ounces)
                                Haptics.success()
                                ToastCenter.shared.show("Added \(Int(ml)) ml water", branded: true)
                            }

                            // A today-only summary (it covers the last 7 days and has a log button).
                            if isToday {
                                RawSnapshotSection(meals: todaysMeals, weekMeals: weekMeals, onOpen: { pushed = .raw },
                                                   onLogRaw: { showRawLog = true })
                                    .transition(.opacity)
                            }
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
        let drinksMl = (todaysHydration?.waterOunces ?? 0) * HydrationSection.mlPerOunce
        let manualSun = sunSessions.filter { cal.isDateInToday($0.start) }.reduce(0) { $0 + $1.minutes }
        return WidgetSnapshot(day: cal.startOfDay(for: .now), calories: todaysMeals.totalCalories, calorieGoal: calorieGoal,
                              waterLitres: (drinksMl + FoodWater.millilitres(in: todaysMeals)) / 1000, waterGoalLitres: 3.5,
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





// MARK: - Header
private struct HomeHeader: View {
    let day: Date
    /// Set when a past day is showing.
    let onToday: (() -> Void)?
    let onSearch: () -> Void
    let onWeather: () -> Void
    private var dateText: String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: day).uppercased()
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
                .contentTransition(.numericText())
        }
    }
    private var actions: some View {
        HStack(spacing: 10) {
            if let onToday {
                Button(action: onToday) {
                    Text("Today").font(.mono(12, .semibold)).tracking(1.2).textCase(.uppercase)
                        .foregroundColor(.ncPrimary)
                        .padding(.horizontal, 16).frame(height: 44)
                        .glass(.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .accessibilityHint("Shows today")
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
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

private struct CycleSection: View {
    let cycle: EatingCycle
    let selected: Date
    let onSelect: (Date) -> Void

    /// The selected day's place in this month's cycle (today's when the selection is in an earlier month).
    private var dayNumber: Int {
        let cal = Calendar.current
        return cal.isDate(selected, equalTo: .now, toGranularity: .month) ? cal.component(.day, from: selected) : cycle.day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                (Text("DAY \(dayNumber) ") + Text("OF \(cycle.length)").foregroundColor(.ncSecondary))
                    .font(.mono(12, .semibold)).tracking(0.96).foregroundColor(.ncPrimary)
                    .contentTransition(.numericText())
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(cycle.ticks.enumerated()), id: \.offset) { _, tick in
                        let isSelected = tick.date == selected
                        Capsule().fill(isSelected ? Color.ncPrimary : tickColor(tick.mark))
                            .frame(maxWidth: .infinity)
                            .frame(height: isSelected || tick.mark == .today ? 22 : 14)
                            .opacity(isSelected || tick.mark != .today ? 1 : 0.5)
                    }
                }
                .frame(height: 22)
                .accessibilityElement()
                .accessibilityLabel("Day \(dayNumber) of \(cycle.length)")
            }
            .padding(.horizontal, Space.margin)

            DateWheel(days: cycle.history, selected: selected, onSelect: onSelect, describe: markDescription)
                .padding(.top, 4)
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
    var isToday = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var progress: Double { goal > 0 ? total / goal : 0 }
    private var reached: Bool { progress >= 1 }
    /// "Left" for today; for a finished day, how far under or over the target it ended.
    private var remaining: String {
        let diff = Int((goal - total).rounded())
        if isToday { return "\(max(0, diff).formatted()) KCAL LEFT" }
        return diff >= 0 ? "\(diff.formatted()) KCAL UNDER" : "\((-diff).formatted()) KCAL OVER"
    }

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
                // Target reached: the rune settles in behind the number. Decorative, so hidden from VoiceOver.
                if reached {
                    AlgizMark().fill(Color.ncPrimary.opacity(0.08))
                        .frame(width: 104, height: 136)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
                VStack(spacing: 6) {
                    Text(Int(total).formatted()).font(.display(52)).tracking(-2.08).foregroundColor(.ncPrimary)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: Int(total))
                    Text("OF \(Int(goal).formatted()) KCAL").font(.mono(12)).tracking(1.92).foregroundColor(.ncSecondary)
                }
            }
            .frame(width: 240, height: 240)
            .animation(.spring(response: 0.6, dampingFraction: 0.75), value: reached)
            .accessibilityElement(children: .combine)
            .onChange(of: reached) { was, now in
                // Celebrate crossing the line today, once per day; not on opening the app already past it.
                guard isToday, !was, now else { return }
                let key = "targetHitDay", day = Date.now.formatted(.iso8601.year().month().day())
                guard UserDefaults.standard.string(forKey: key) != day else { return }
                UserDefaults.standard.set(day, forKey: key)
                Haptics.success()
                ToastCenter.shared.show("Target hit", branded: true)
            }

            Text(remaining)
                .font(.mono(13)).tracking(1.04).foregroundColor(.ncSecondary)
                .contentTransition(.numericText())
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

// MARK: - Micronutrients and sunlight
/// The day's vitamins and minerals (how many are met and the three lowest) beside minutes of sunlight against
/// the goal. Side by side when they fit; stacked at large text sizes.
private struct MicrosSunSection: View {
    let micros: [NutrientInfo]
    let sunMinutes: Double
    let sunGoal: Double
    /// nil on past days (the Data tab shows today).
    let onMicros: (() -> Void)?
    let onSun: () -> Void

    private var met: Int { micros.filter(\.isMet).count }
    private var lowest: [NutrientInfo] { Array(micros.sorted { $0.progress < $1.progress }.prefix(3)) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                microsBlock.frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Color.ncPrimary.opacity(0.14)).frame(width: 1).padding(.horizontal, 16)
                sunBlock.frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 24) {
                microsBlock
                sunBlock
            }
        }
    }

    private var microsBlock: some View {
        Button { onMicros?() } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Micronutrients").monoLabel().lineLimit(1).fixedSize()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(met)").font(.metric(26)).foregroundColor(.ncPrimary).contentTransition(.numericText())
                    Text("/\(micros.count) MET").font(.mono(11)).foregroundColor(.ncSecondary).lineLimit(1).fixedSize()
                }
                ForEach(lowest) { n in
                    let status = IntakeStatus(progress: n.progress)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.name).font(.ui(size: 12)).foregroundColor(.ncPrimary).lineLimit(1)
                        LineGauge(value: n.progress, tint: status.bar, height: 3)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onMicros == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Micronutrients: \(met) of \(micros.count) met. Lowest: \(lowest.map { "\($0.name) \($0.percentage)%" }.joined(separator: ", "))")
        .accessibilityHint(onMicros == nil ? "" : "Opens Data")
    }

    private var sunBlock: some View {
        Button(action: onSun) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sunlight").monoLabel().lineLimit(1).fixedSize()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(sunMinutes))").font(.metric(26)).foregroundColor(.ncPrimary).contentTransition(.numericText())
                    Text("/\(Int(sunGoal)) MIN").font(.mono(11)).foregroundColor(.ncSecondary).lineLimit(1).fixedSize()
                }
                LineGauge(value: sunGoal > 0 ? sunMinutes / sunGoal : 0, tint: sunMinutes >= sunGoal ? .ncMoss : .ncPrimary, height: 3)
                Image(systemName: sunMinutes >= sunGoal ? "sun.max.fill" : "sun.max")
                    .font(.system(size: 22, weight: .regular)).foregroundColor(.ncPrimary.opacity(0.85))
                    .symbolEffect(.bounce, value: sunMinutes >= sunGoal)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sunlight: \(Int(sunMinutes)) of \(Int(sunGoal)) minutes")
        .accessibilityHint("Opens Sun")
    }
}

// MARK: - Hydration
/// Water for the day, from drinks and from food, against the goal. Water can only be added (pick an amount on the
/// wheel, tap the centred one); it never goes down. Past days show the bar only.
struct HydrationSection: View {
    static let mlPerOunce = 29.5735

    let drinksMl: Double
    let foodMl: Double
    let readOnly: Bool
    let onAdd: (Double) -> Void

    private let goalMl = 3500.0
    private static let amounts: [Double] = [150, 250, 330, 500, 750, 1000]
    @State private var amount = 250.0

    private var totalMl: Double { drinksMl + foodMl }
    private func litres(_ ml: Double) -> String { String(format: "%.1f", ml / 1000) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hydration").monoLabel()
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(litres(totalMl)).font(.metric(28)).foregroundColor(.ncPrimary)
                        .contentTransition(.numericText(value: totalMl))
                    Text("/ \(litres(goalMl)) L").font(.mono(12)).foregroundColor(.ncSecondary)
                }
            }

            // Drinks (solid) then food water (lighter) along one track; full width is the goal.
            GeometryReader { geo in
                let w = geo.size.width
                let drinksW = min(1, drinksMl / goalMl) * w
                let foodW = min(max(0, 1 - drinksMl / goalMl), foodMl / goalMl) * w
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.clear).glass(.clear, in: Capsule())
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.ncPrimary).frame(width: drinksW)
                        Rectangle().fill(Color.ncPrimary.opacity(0.45)).frame(width: foodW)
                    }
                    .clipShape(Capsule())
                    .padding(3)
                }
            }
            .frame(height: 16)
            .accessibilityElement()
            .accessibilityLabel("Hydration")
            .accessibilityValue("\(litres(totalMl)) of \(litres(goalMl)) litres, \(litres(foodMl)) from food")

            Text("DRINKS \(litres(drinksMl)) L · FOOD \(litres(foodMl)) L")
                .font(.mono(11)).tracking(0.9).foregroundColor(.ncSecondary)
                .contentTransition(.numericText())

            if !readOnly {
                ArcWheel(items: Self.amounts, selection: $amount, onTapSelected: { onAdd(amount) }) { ml, on in
                    Text(on ? "+ \(label(ml))" : label(ml))
                        .font(.mono(12, .semibold)).tracking(1.1)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundColor(on ? .ncOnPrimary : .ncPrimary)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background {
                            if on { Capsule().fill(Color.ncPrimary) } else { Capsule().fill(Color.clear).glass(.clear, in: Capsule()) }
                        }
                        .contentShape(Capsule())
                        .animation(.smooth(duration: 0.25), value: on)
                }
                .accessibilityRepresentation {
                    Button("Add \(label(amount)) water") { onAdd(amount) }
                    Picker("Amount", selection: $amount) {
                        ForEach(Self.amounts, id: \.self) { Text(label($0)).tag($0) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ ml: Double) -> String { ml >= 1000 ? "1 L" : "\(Int(ml)) ML" }
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
    /// Past days: no removing and no logging.
    var readOnly = false
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
                        if readOnly {
                            MealRow(meal: meal, onDelete: nil)
                        } else {
                            MealRow(meal: meal) { pendingDelete = meal }
                                .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .move(edge: .leading))))
                                .contextMenu {
                                    Button(role: .destructive) { pendingDelete = meal } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                } else if readOnly {
                    BrandEmptyState(message: "No meals logged this day")
                }
            }
            .padding(.horizontal, Space.margin)

            if !readOnly {
                Button("Log food", action: onAdd)
                    .buttonStyle(.vitalis)
                    .padding(Space.margin)
            }
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
    /// nil on past days: the row is view-only.
    let onDelete: (() -> Void)?

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
            if let onDelete {
                Button(action: onDelete) {
                    Text("×").font(.ui(size: 22)).foregroundColor(.ncSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(meal.foodName)")
                .accessibilityHint("Asks before removing")
            }
        }
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { Hairline(opacity: 0.28) }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Date wheel

/// The last 30 days as pills on a dial, like the map's category wheel: scroll back through past days and the one
/// that snaps to the centre is the day Home shows. Tapping a pill spins it there. Today sits at the right end.
private struct DateWheel: View {
    let days: [EatingCycle.Day]
    let selected: Date
    let onSelect: (Date) -> Void
    let describe: (EatingCycle.Mark) -> String
    @State private var centered: Date?

    private let pillWidth: CGFloat = 50

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days) { day in
                        pill(day)
                            .visualEffect { content, proxy in
                                // -1 at the left edge of the wheel, 0 in the centre, 1 at the right edge.
                                let width = proxy.bounds(of: .scrollView)?.width ?? 1
                                let d = max(-1, min(1, (proxy.frame(in: .scrollView).midX - width / 2) / (width / 2)))
                                return content
                                    .rotationEffect(.degrees(d * 14), anchor: .center)
                                    .offset(y: d * d * 16)
                                    .scaleEffect(1 - abs(d) * 0.16)
                                    .opacity(1 - abs(d) * 0.55)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            // Room on both sides so the first and last pills can reach the centre.
            .safeAreaPadding(.horizontal, max(0, (geo.size.width - pillWidth) / 2))
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centered, anchor: .center)
            .scrollClipDisabled()
        }
        .frame(height: 92)
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
                Text(day.weekday).font(.mono(11, .semibold)).tracking(0.8).opacity(0.8)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("\(day.number)").font(.display(17))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Circle().fill(dotColor(day.mark, on: on)).frame(width: 6, height: 6)
            }
            .foregroundColor(on ? .ncOnPrimary : .ncPrimary)
            .frame(width: pillWidth)
            .padding(.top, 10).padding(.bottom, 9)
            .background {
                if on {
                    Capsule().fill(Color.ncPrimary)
                } else {
                    Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(Color.white.opacity(0.06)))
                        .environment(\.colorScheme, .dark)
                }
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0 : 0.16), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.3), value: on)
        .accessibilityLabel("\(day.id.formatted(.dateTime.weekday(.wide).month(.wide).day())), \(describe(day.mark))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func dotColor(_ m: EatingCycle.Mark, on: Bool) -> Color {
        switch m {
        case .onTarget: .ncMoss
        case .offTarget: .ncEmber
        case .today: on ? .ncOnPrimary : .ncPrimary
        case .upcoming, .empty: on ? .ncOnPrimary.opacity(0.3) : .ncPrimary.opacity(0.25)
        }
    }
}
