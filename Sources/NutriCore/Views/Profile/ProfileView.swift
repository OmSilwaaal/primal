import SwiftUI
import SwiftData

enum ProfileRoute: Hashable { case settings, goals }

/// The Profile tab: a top bar with "<name> · Profile" and Settings, then Body / Goals / Plan pills.
/// • Body: the Weight card (last 7 days as a line, tap a day to move the marker) and capsule stats — Height, Age,
///   Goal and any added ones — each shown as a dot-matrix number; tap one to edit it.
/// • Goals: goal weight with progress from start to now to goal, daily energy, and this week's days in range.
/// • Plan: today's calorie target and the macro targets with today's progress, and Edit plan.
/// Raw, Sun and Friends stay reachable at the bottom; Pro, legal and signing out live in Settings.
struct ProfileView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case body = "Body", goals = "Goals", plan = "Plan"
        var id: Self { self }
    }

    enum Sheet: Identifiable {
        case edit(StatField), addStat, weightHistory, plan
        var id: String {
            switch self {
            case .edit(let f): "edit-\(f.rawValue)"
            case .addStat: "add"
            case .weightHistory: "weight"
            case .plan: "plan"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [UserProfile]
    @Query(sort: \BiomarkerReading.date) private var readings: [BiomarkerReading]
    @Query private var weekMeals: [MealEntry]
    @StateObject private var social = SocialService.shared

    @State private var tab: Tab = .body
    @State private var route: ProfileRoute?
    @State private var pushed: SecondaryScreen?
    @State private var sheet: Sheet?
    /// Which of the Weight card's seven days is selected (6 = today).
    @State private var selectedDay = 6
    @State private var removing: ExtraStat?
    /// Extra stats added with the + capsule, comma-separated.
    @AppStorage("profileExtraStats") private var extraStatsRaw = ""

    init() {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now
        _weekMeals = Query(filter: #Predicate<MealEntry> { $0.date >= start })
    }

    private var profile: UserProfile? { profiles.first }
    private var extraStats: [ExtraStat] { extraStatsRaw.split(separator: ",").compactMap { ExtraStat(rawValue: String($0)) } }

    private static let activities: [(String, String)] = [
        ("sedentary", "Sedentary"), ("light", "Light"), ("moderate", "Moderate"), ("active", "Active"), ("veryActive", "Very active"),
    ]

    var body: some View {
        NavigationStack {
            // No backdrop here: ContentView draws one that stays still while tabs change.
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Bento.gap) {
                    topBar.padding(.top, 4)
                    if let profile {
                        pills
                        Group {
                            switch tab {
                            case .body: bodyTab(profile)
                            case .goals: goalsTab(profile)
                            case .plan: planTab(profile)
                            }
                        }
                        .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
                    } else {
                        setUp
                    }
                    more.padding(.top, 8)
                }
                .padding(.horizontal, Bento.margin)
                .padding(.bottom, 120)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.88), value: tab)
            }
            .glassLightFollowsScroll()
            .sharedBackdropRoot()
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("Profile") // names the back button on pushed screens
            .navigationDestination(item: $pushed) { $0.destination }
            .navigationDestination(item: $route) { route in
                switch route {
                case .settings: SettingsView().pushedScreen()
                case .goals: GoalsDestination(month: MonthMath.start(of: .now)).pushedScreen()
                }
            }
            .sheet(item: $sheet) { sheet in
                if let profile { sheetContent(sheet, profile) }
            }
            .confirmationDialog("Remove \(removing?.title ?? "stat") from Profile?",
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible, presenting: removing) { stat in
                Button("Remove", role: .destructive) { setExtra(stat, on: false) }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            if isPresented {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(BentoRoundButtonStyle(size: 48))
                    .accessibilityLabel("Back")
            } else {
                // As a tab there's nowhere to go back to: the rune holds the corner instead.
                AlgizMark().fill(Mono.text).frame(width: 14, height: 18)
                    .frame(width: 48, height: 48)
                    .liquidGlassPanel(in: Circle())
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            Text(profile.map { "\(displayName($0)) · Profile" } ?? "Profile")
                .font(.ui(size: 17, weight: .semibold)).foregroundColor(Mono.text)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button { route = .settings } label: { Image(systemName: "gearshape") }
                .buttonStyle(BentoRoundButtonStyle(size: 48))
                .accessibilityLabel("Settings")
        }
    }

    private var pills: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { t in
                let on = tab == t
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    tab = t
                } label: {
                    Text(t.rawValue).font(.ui(size: 15, weight: .semibold))
                        .foregroundColor(on ? Mono.onWhite : Mono.text)
                        .frame(maxWidth: .infinity).frame(minHeight: 44)
                        .background {
                            if on {
                                Capsule().fill(Mono.text)
                            } else {
                                Capsule().fill(Color.clear).liquidGlassPanel(in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.96))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    // MARK: - Body tab

    /// The last seven days of weight, oldest first: each day's latest reading, carrying the previous one forward
    /// on days without; today falls back to the profile's weight.
    private func weekWeights(_ profile: UserProfile) -> [(day: Date, kg: Double)] {
        let cal = Calendar.current, today = cal.startOfDay(for: .now)
        let weights = readings.filter { $0.kind == BiomarkerKind.weight.rawValue }
        return (0..<7).reversed().compactMap { back -> (Date, Double)? in
            guard let day = cal.date(byAdding: .day, value: -back, to: today),
                  let end = cal.date(byAdding: .day, value: 1, to: day) else { return nil }
            let latest = weights.last { $0.date < end }?.value
            if back == 0 {
                let todays = weights.last { cal.isDate($0.date, inSameDayAs: day) }?.value
                return (day, todays ?? profile.weightKg)
            }
            return (day, latest ?? profile.weightKg)
        }
    }

    private func bodyTab(_ profile: UserProfile) -> some View {
        VStack(spacing: Bento.gap) {
            WeightCard(days: weekWeights(profile), selected: $selectedDay) { sheet = .weightHistory }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                StatCapsule(label: "Height", value: "\(Int(profile.heightCm))", unit: "cm", glow: .ncPrimary) {
                    sheet = .edit(.height)
                }
                StatCapsule(label: "Age", value: "\(profile.age)", unit: "yrs", glow: .ncPrimary) {
                    sheet = .edit(.age)
                }
                StatCapsule(label: "Goal", value: NutrientRow.dec(profile.goalWeightKg), unit: "kg", glow: .ncMoss) {
                    sheet = .edit(.goal)
                }
                ForEach(extraStats) { stat in
                    StatCapsule(label: stat.title, value: stat.value(profile: profile, readings: readings) ?? "—",
                                unit: stat.unit, glow: .ncEmber) { removing = stat }
                }
                Button { sheet = .addStat } label: {
                    Image(systemName: "plus").font(.ui(size: 22, weight: .semibold)).foregroundColor(Mono.onWhite)
                        .frame(maxWidth: .infinity).frame(height: 84)
                        .background(Capsule().fill(Mono.text))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.96))
                .accessibilityLabel("Add a stat")
            }
        }
    }

    // MARK: - Goals tab

    private func goalsTab(_ profile: UserProfile) -> some View {
        let weights = readings.filter { $0.kind == BiomarkerKind.weight.rawValue }
        let horizon = Calendar.current.date(byAdding: .day, value: -180, to: .now) ?? .now
        let start = weights.first { $0.date >= horizon }?.value ?? profile.weightKg
        let now = profile.weightKg, goal = profile.goalWeightKg
        let activity = Self.activities.first { $0.0 == profile.activityLevel }?.1.lowercased() ?? profile.activityLevel
        let byDay = caloriesByDay()
        let cal = Calendar.current, today = cal.startOfDay(for: .now)
        let week = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let inRange = week.map { DayGoal(kcal: byDay[$0] ?? 0, goal: profile.dailyCalorieGoal) == .onTarget }

        return VStack(spacing: Bento.gap) {
            GoalWeightTile(start: start, now: now, goal: goal) { sheet = .edit(.goal) }

            VStack(alignment: .leading, spacing: 10) {
                Text("Daily energy").font(.ui(size: 13, weight: .medium)).foregroundColor(Mono.label)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    DotMatrixText(text: Int(profile.dailyCalorieGoal).formatted(), pitch: 5)
                    Text("kcal").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(Mono.label)
                }
                Text("From your weight, height, age and \(activity) activity.")
                    .font(.ui(size: 13)).foregroundColor(Mono.label).fixedSize(horizontal: false, vertical: true)
            }
            .bentoTile(padding: 18, art: .sun)
            .accessibilityElement(children: .combine)

            Button { route = .goals } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("This week").font(.ui(size: 13, weight: .medium)).foregroundColor(Mono.label)
                        Spacer()
                        Image(systemName: "chevron.right").font(.ui(size: 12, weight: .semibold)).foregroundColor(Mono.label)
                    }
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { i, day in
                            VStack(spacing: 6) {
                                ZStack {
                                    if inRange[i] {
                                        Circle().fill(Color.ncMoss)
                                        Image(systemName: "checkmark").font(.ui(size: 13, weight: .bold)).foregroundColor(Mono.onWhite)
                                    } else {
                                        Circle().strokeBorder(Color.ncPrimary.opacity(0.4), lineWidth: 1.5)
                                    }
                                }
                                .frame(width: 34, height: 34)
                                Text(day.formatted(.dateTime.weekday(.narrow))).font(.mono(11, .semibold))
                                    .foregroundColor(cal.isDateInToday(day) ? Mono.text : Mono.label)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Text("\(inRange.filter { $0 }.count) of 7 days in range")
                        .font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
                }
                .bentoTile(padding: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("This week")
            .accessibilityValue("\(inRange.filter { $0 }.count) of 7 days in range")
            .accessibilityHint("Opens your goals calendar")
        }
    }

    private func caloriesByDay() -> [Date: Double] {
        var out: [Date: Double] = [:]
        for m in weekMeals { out[Calendar.current.startOfDay(for: m.date), default: 0] += m.calories }
        return out
    }

    // MARK: - Plan tab

    private func planTab(_ profile: UserProfile) -> some View {
        let goals = NutrientGoals.from(profile)
        let today = weekMeals.filter { Calendar.current.isDateInToday($0.date) }
        let rows: [(String, Double, Double)] = [
            ("Protein", today.totalProtein, goals.protein),
            ("Carbs", today.totalCarbs, goals.carbohydrates),
            ("Fat", today.totalFat, goals.fat),
            ("Fiber", today.totalFiber, goals.fiber),
        ]
        return VStack(spacing: Bento.gap) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily targets").font(.ui(size: 13, weight: .medium)).foregroundColor(Mono.label)
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    DotMatrixText(text: Int(goals.calories).formatted(), pitch: 5)
                    Text("kcal").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(Mono.label)
                }
                .accessibilityElement(children: .combine)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        let (name, cur, target) = row
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(name).font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
                                Spacer()
                                Text("\(Int(target.rounded())) g").font(.mono(12)).foregroundColor(Mono.text)
                            }
                            BentoBar(value: target > 0 ? cur / target : 0, height: 4)
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .top) {
                            if i > 0 { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(name)
                        .accessibilityValue("Target \(Int(target.rounded())) grams, \(Int(cur.rounded())) today")
                    }
                }
            }
            .bentoTile(padding: 18, art: .meat)

            Button { sheet = .plan } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edit plan").font(.ui(size: 16, weight: .semibold)).foregroundColor(Mono.text)
                        Text("Sex and activity set your targets").font(.ui(size: 12)).foregroundColor(Mono.label)
                    }
                    Spacer()
                    Image(systemName: "pencil").font(.ui(size: 16, weight: .semibold)).foregroundColor(Mono.onWhite)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Mono.text))
                        .accessibilityHidden(true)
                }
                .padding(.leading, 24).padding(.trailing, 10)
                .frame(minHeight: 64)
                .liquidGlassPanel(in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle(scale: 0.98))
        }
    }

    // MARK: - No profile

    private var setUp: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up your profile so your targets can be worked out for you.")
                .font(.bentoBody).foregroundColor(Mono.text)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(destination: ProfileSetupView()) { Text("Set up profile") }
                .buttonStyle(.bentoPrimary)
        }
        .bentoTile(padding: 18, art: .sprig)
    }

    // MARK: - More

    /// The screens that moved out of the tab bar (Settings is in the top bar).
    private var more: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("More").font(.bentoLabel).foregroundColor(Mono.label).padding(.bottom, 4)
            row("Raw", "Diet position, food safety, organ rotation", icon: "leaf", first: true) { pushed = .raw }
            row("Sun", "Time outside and today's vitamin D window", icon: "sun.max") { pushed = .sun }
            row("Friends", "Eat together, shared meals", icon: "person.2") { pushed = .friends }
        }
        .bentoTile(padding: 18)
    }

    private func row(_ title: String, _ detail: String, icon: String, first: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.ui(size: 15, weight: .medium)).foregroundColor(Mono.text)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
                    Text(detail).font(.ui(size: 12)).foregroundColor(Mono.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.ui(size: 12, weight: .semibold)).foregroundColor(Mono.label)
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if !first { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
            }
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Sheets

    @ViewBuilder private func sheetContent(_ sheet: Sheet, _ profile: UserProfile) -> some View {
        switch sheet {
        case .edit(.height):
            StatEditor(title: "Height", unit: "cm", range: 120...220, step: 1, major: 10, value: profile.heightCm) {
                profile.heightCm = $0; save("Height saved")
            }
        case .edit(.age):
            StatEditor(title: "Age", unit: "yrs", range: 13...100, step: 1, major: 5, value: Double(profile.age)) {
                profile.age = Int($0); save("Age saved")
            }
        case .edit(.goal):
            StatEditor(title: "Goal weight", unit: "kg", range: 30...200, step: 1, major: 10, value: profile.goalWeightKg.rounded()) {
                profile.goalWeightKg = $0; save("Goal saved")
            }
        case .addStat:
            AddStatSheet(shown: Set(extraStats)) { stat, on in setExtra(stat, on: on) }
        case .weightHistory:
            WeightHistorySheet(current: profile.weightKg,
                               history: readings.filter { $0.kind == BiomarkerKind.weight.rawValue }.reversed()) { kg in
                let reading = BiomarkerReading()
                reading.date = .now
                reading.kind = BiomarkerKind.weight.rawValue
                reading.value = kg
                reading.source = "manual"
                modelContext.insert(reading)
                profile.weightKg = kg
                save("Weight logged")
            }
        case .plan:
            PlanEditor(sex: profile.isMale ? "Male" : "Female", activity: profile.activityLevel,
                       activities: Self.activities, profile: profile) { sex, activity in
                profile.sex = sex
                profile.activityLevel = activity
                save("Plan saved")
            }
        }
    }

    private func setExtra(_ stat: ExtraStat, on: Bool) {
        var list = extraStats.filter { $0 != stat }
        if on { list.append(stat) }
        extraStatsRaw = list.map(\.rawValue).joined(separator: ",")
    }

    private func save(_ message: String) {
        try? modelContext.save()
        Haptics.success()
        ToastCenter.shared.show(message)
    }

    private func displayName(_ profile: UserProfile) -> String {
        if let name = social.myProfile?.name, !name.isEmpty { return name }
        return profile.name.isEmpty ? "Your" : profile.name
    }
}

// MARK: - Stats

enum StatField: String { case height, age, goal }

/// Stats that can be added to Body with the + capsule, read from Health / Biomarkers readings.
enum ExtraStat: String, CaseIterable, Identifiable {
    case bmi, bodyFat, waist, restingHR
    var id: Self { self }

    var title: String {
        switch self {
        case .bmi: "BMI"
        case .bodyFat: "Body fat"
        case .waist: "Waist"
        case .restingHR: "Resting HR"
        }
    }
    var unit: String {
        switch self {
        case .bmi: ""
        case .bodyFat: "%"
        case .waist: "cm"
        case .restingHR: "bpm"
        }
    }
    var detail: String {
        switch self {
        case .bmi: "From your weight and height"
        case .bodyFat: "Latest reading from Health or Biomarkers"
        case .waist: "Latest reading from Health or Biomarkers"
        case .restingHR: "Latest reading from Health or Biomarkers"
        }
    }

    func value(profile: UserProfile, readings: [BiomarkerReading]) -> String? {
        let kind: BiomarkerKind
        switch self {
        case .bmi:
            let m = profile.heightCm / 100
            guard m > 0 else { return nil }
            return String(format: "%.1f", profile.weightKg / (m * m))
        case .bodyFat: kind = .bodyFat
        case .waist: kind = .waist
        case .restingHR: kind = .restingHR
        }
        guard let v = readings.last(where: { $0.kind == kind.rawValue })?.value else { return nil }
        return NutrientRow.dec(v)
    }
}

/// An 84 pt capsule: a small label over the value in dot-matrix numerals and its unit, with a faint glow.
private struct StatCapsule: View {
    let label: String
    let value: String
    let unit: String
    let glow: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.ui(size: 12, weight: .medium)).foregroundColor(Mono.label).lineLimit(1)
                HStack(alignment: .lastTextBaseline, spacing: 5) {
                    DotMatrixText(text: value, pitch: 3.4)
                    if !unit.isEmpty {
                        Text(unit).font(.mono(11, .semibold)).tracking(0.66).textCase(.uppercase).foregroundColor(Mono.label)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .frame(height: 84)
            .background {
                RadialGradient(colors: [glow.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 140)
                    .clipShape(Capsule())
            }
            .liquidGlassPanel(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value) \(unit)")
        .accessibilityHint("Edits \(label.lowercased())")
    }
}

// MARK: - Weight card

/// The week of weight as a smooth line over seven day circles. The selected day carries a white marker with a soft
/// ring and a dashed drop line to its circle; tapping a circle moves the marker along the curve.
private struct WeightCard: View {
    let days: [(day: Date, kg: Double)]
    @Binding var selected: Int
    let onHistory: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 44, style: .continuous)
        let sel = min(max(selected, 0), max(0, days.count - 1))
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Weight").font(.ui(size: 20, weight: .bold)).foregroundColor(Mono.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: onHistory) { Image(systemName: "arrow.up.right") }
                    .buttonStyle(BentoRoundButtonStyle(size: 36))
                    .accessibilityLabel("Weight history")
            }

            GeometryReader { geo in
                let w = geo.size.width
                let chartTop: CGFloat = 18, chartBottom: CGFloat = 104, circlesY: CGFloat = 140
                let values = days.map(\.kg)
                let lo = (values.min() ?? 0) - 0.6, hi = (values.max() ?? 1) + 0.6
                let points = days.indices.map { i -> CGPoint in
                    let x = w * (CGFloat(i) + 0.5) / CGFloat(max(1, days.count))
                    let t = hi > lo ? (values[i] - lo) / (hi - lo) : 0.5
                    return CGPoint(x: x, y: chartBottom - (chartBottom - chartTop) * t)
                }
                ZStack(alignment: .topLeading) {
                    SmoothLine(points: points)
                        .stroke(Color.ncPrimary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    if points.indices.contains(sel) {
                        let p = points[sel]
                        // Dashed drop line from the marker to the day circles.
                        Path { path in
                            path.move(to: CGPoint(x: p.x, y: p.y + 14))
                            path.addLine(to: CGPoint(x: p.x, y: circlesY - 22))
                        }
                        .stroke(Color.ncPrimary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        ZStack {
                            Circle().fill(Color.white.opacity(0.14)).frame(width: 40, height: 40)
                            Circle().fill(Color.white).frame(width: 24, height: 24)
                                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                        }
                        .position(p)
                    }
                    ForEach(days.indices, id: \.self) { i in
                        let on = i == sel
                        Button {
                            Haptics.selection()
                            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82)) { selected = i }
                        } label: {
                            Text(days[i].day.formatted(.dateTime.weekday(.narrow)))
                                .font(.mono(12, .semibold))
                                .foregroundColor(on ? Mono.onWhite : Mono.text)
                                .frame(width: 38, height: 38)
                                .background {
                                    if on { Circle().fill(Mono.text) }
                                    else { Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1) }
                                }
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .position(x: points.indices.contains(i) ? points[i].x : 0, y: circlesY)
                        .accessibilityLabel(days[i].day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .accessibilityValue("\(String(format: "%.1f", days[i].kg)) kilograms")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .frame(height: 164)

            if days.indices.contains(sel) {
                Text("\(days[sel].day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · \(String(format: "%.1f", days[sel].kg)) kg")
                    .font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(22)
        .background {
            ZStack {
                RadialGradient(colors: [Color.ncMoss.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 240)
                RadialGradient(colors: [Color.ncEmber.opacity(0.18), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 220)
            }
            .clipShape(shape)
        }
        .glassSheen(in: shape, strength: 0.8)
        .glass(.tinted, in: shape)
    }
}

// MARK: - Goal weight

/// The goal in dot-matrix numerals, a status word in an outlined pill, and a bar from where you started through where
/// you are now to the goal.
private struct GoalWeightTile: View {
    let start: Double
    let now: Double
    let goal: Double
    let onEdit: () -> Void

    private var progress: Double {
        guard abs(start - goal) > 0.05 else { return abs(now - goal) < 0.5 ? 1 : 0 }
        return min(max((start - now) / (start - goal), 0), 1)
    }
    private var status: String {
        if abs(now - goal) < 0.5 { return "Reached" }
        return abs(now - goal) <= abs(start - goal) + 0.05 ? "On track" : "Off track"
    }

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text("Goal weight").font(.ui(size: 13, weight: .medium)).foregroundColor(Mono.label)
                    Spacer()
                    Text(status).font(.mono(11, .semibold)).tracking(0.66).textCase(.uppercase)
                        .foregroundColor(status == "Off track" ? .ncEmber : .ncMoss)
                        .padding(.horizontal, 10).frame(minHeight: 26)
                        .overlay(Capsule().strokeBorder(status == "Off track" ? Color.ncEmber : Color.ncMoss, lineWidth: 1))
                }
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    DotMatrixText(text: NutrientRow.dec(goal), pitch: 5)
                    Text("kg").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(Mono.label)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.ncPrimary.opacity(0.15))
                        Capsule().fill(Color.ncMoss).frame(width: max(6, geo.size.width * progress))
                        Circle().fill(Color.white).frame(width: 12, height: 12)
                            .offset(x: max(0, geo.size.width * progress - 6))
                    }
                }
                .frame(height: 6)
                HStack {
                    label("Start", start)
                    Spacer()
                    label("Now", now)
                    Spacer()
                    label("Goal", goal)
                }
            }
            .bentoTile(padding: 18, art: .leaf)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Goal weight \(NutrientRow.dec(goal)) kilograms, \(status)")
        .accessibilityValue("Started at \(NutrientRow.dec(start)), now \(NutrientRow.dec(now))")
        .accessibilityHint("Edits your goal weight")
    }

    private func label(_ title: String, _ kg: Double) -> some View {
        Text("\(title) \(NutrientRow.dec(kg))").font(.mono(11, .semibold)).tracking(0.66).textCase(.uppercase)
            .foregroundColor(Mono.label)
    }
}

// MARK: - Dot-matrix numerals

/// Numbers drawn in a 5 × 7 dot font, in Paper. `pitch` is the distance between dot centres.
struct DotMatrixText: View {
    let text: String
    var pitch: CGFloat = 4
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

    private static let glyphs: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ".": ["0", "0", "0", "0", "0", "0", "1"],
        ",": ["0", "0", "0", "0", "0", "1", "1"],
        "-": ["000", "000", "000", "111", "000", "000", "000"],
        "—": ["000", "000", "000", "111", "000", "000", "000"],
        " ": ["00", "00", "00", "00", "00", "00", "00"],
    ]

    private var glyphs: [[String]] { text.map { Self.glyphs[$0] ?? Self.glyphs[" "]! } }

    var body: some View {
        let p = pitch * min(scale, 1.6)
        let columns = glyphs.reduce(0) { $0 + ($1.first?.count ?? 0) } + max(0, glyphs.count - 1)
        Canvas { ctx, _ in
            var x: CGFloat = 0
            let r = p * 0.36
            for g in glyphs {
                let width = g.first?.count ?? 0
                for (row, bits) in g.enumerated() {
                    for (col, bit) in bits.enumerated() where bit == "1" {
                        let c = CGPoint(x: x + CGFloat(col) * p + p / 2, y: CGFloat(row) * p + p / 2)
                        ctx.fill(Circle().path(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                 with: .color(.ncPrimary))
                    }
                }
                x += CGFloat(width + 1) * p
            }
        }
        .frame(width: CGFloat(columns) * p, height: 7 * p)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

// MARK: - Sheets

/// Sets one stat on the line slider.
private struct StatEditor: View {
    let title: String
    let unit: String
    let range: ClosedRange<Int>
    let step: Int
    let major: Int
    @State var value: Double
    let onSave: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    init(title: String, unit: String, range: ClosedRange<Int>, step: Int, major: Int, value: Double,
         onSave: @escaping (Double) -> Void) {
        self.title = title; self.unit = unit; self.range = range; self.step = step; self.major = major
        _value = State(initialValue: min(max(value, Double(range.lowerBound)), Double(range.upperBound)))
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.ui(size: 22, weight: .bold)).foregroundColor(Mono.text)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                DotMatrixText(text: "\(Int(value))", pitch: 5)
                Text(unit).font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(Mono.label)
            }
            .frame(maxWidth: .infinity)
            LineRuler(amount: $value, range: range, step: step, major: major, spokenUnit: unit) { "\($0)" }
                .padding(.horizontal, -20)
            Button("Save") { onSave(value); dismiss() }.buttonStyle(.bentoPrimary)
        }
        .padding(20)
        .presentationDetents([.height(360)])
        .glassSheetBackground()
        .presentationCornerRadius(Bento.radius)
    }
}

/// Choose which extra stats show on Body.
private struct AddStatSheet: View {
    let shown: Set<ExtraStat>
    let onToggle: (ExtraStat, Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a stat").font(.ui(size: 22, weight: .bold)).foregroundColor(Mono.text)
            VStack(spacing: 0) {
                ForEach(Array(ExtraStat.allCases.enumerated()), id: \.element) { i, stat in
                    let on = shown.contains(stat)
                    Button {
                        Haptics.selection()
                        onToggle(stat, !on)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stat.title).font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
                                Text(stat.detail).font(.ui(size: 12)).foregroundColor(Mono.label)
                            }
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
                                .font(.ui(size: 20)).foregroundColor(on ? .ncMoss : Mono.text)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                        .overlay(alignment: .top) {
                            if i > 0 { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
                        }
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.98))
                    .accessibilityValue(on ? "Shown" : "Not shown")
                }
            }
            .bentoTile(padding: 16)
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.medium])
        .glassSheetBackground()
        .presentationCornerRadius(Bento.radius)
    }
}

/// Weight readings, newest first, and logging today's weight in half-kilo steps.
private struct WeightHistorySheet: View {
    let current: Double
    let history: [BiomarkerReading]
    let onLog: (Double) -> Void
    /// The slider works in half kilos.
    @State private var halves: Double
    @Environment(\.dismiss) private var dismiss

    init(current: Double, history: [BiomarkerReading], onLog: @escaping (Double) -> Void) {
        self.current = current
        self.history = history
        self.onLog = onLog
        _halves = State(initialValue: min(max((current * 2).rounded(), 60), 500))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weight").font(.ui(size: 22, weight: .bold)).foregroundColor(Mono.text)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                DotMatrixText(text: String(format: "%.1f", halves / 2), pitch: 5)
                Text("kg").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(Mono.label)
            }
            .frame(maxWidth: .infinity)
            LineRuler(amount: $halves, range: 60...500, step: 1, major: 10, spokenUnit: "half kilograms") {
                "\($0 / 2)"
            }
            .padding(.horizontal, -20)
            Button("Log \(String(format: "%.1f", halves / 2)) kg today") { onLog(halves / 2); dismiss() }
                .buttonStyle(.bentoPrimary)

            Text("History").font(.bentoLabel).foregroundColor(Mono.label).padding(.top, 6)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if history.isEmpty {
                        Text("No weight readings yet. Log one above, or sync from Apple Health on Biomarkers.")
                            .font(.ui(size: 13)).foregroundColor(Mono.label)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    ForEach(Array(history.prefix(60).enumerated()), id: \.element.id) { i, r in
                        HStack {
                            Text(r.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                                .font(.ui(size: 14)).foregroundColor(Mono.text)
                            Spacer()
                            Text("\(String(format: "%.1f", r.value)) kg").font(.mono(12)).foregroundColor(Mono.text)
                        }
                        .frame(minHeight: 44)
                        .overlay(alignment: .top) {
                            if i > 0 { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(20)
        .presentationDetents([.large])
        .glassSheetBackground()
        .presentationCornerRadius(Bento.radius)
    }
}

/// Sex and activity, with the daily energy they work out to.
private struct PlanEditor: View {
    @State var sex: String
    @State var activity: String
    let activities: [(String, String)]
    let profile: UserProfile
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var energy: Double {
        UserProfile.tdee(male: sex == "Male", weightKg: profile.weightKg, heightCm: profile.heightCm,
                         age: profile.age, activity: activity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit plan").font(.ui(size: 22, weight: .bold)).foregroundColor(Mono.text)
            BentoSegmented(options: [("Male", "Male"), ("Female", "Female")], selection: $sex)
            Text("Activity").font(.bentoLabel).foregroundColor(Mono.label)
            FlowLayout(spacing: 8) {
                ForEach(activities, id: \.0) { key, label in
                    let on = activity == key
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { activity = key }
                    } label: {
                        Text(label).font(.ui(size: 14, weight: .semibold))
                            .foregroundColor(on ? Mono.onWhite : Mono.text)
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .background {
                                Capsule().fill(on ? Mono.text : Color.white.opacity(0.08))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0 : 0.16), lineWidth: 1))
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.96))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("Daily energy").font(.bentoLabel).foregroundColor(Mono.label)
                Spacer()
                DotMatrixText(text: Int(energy).formatted(), pitch: 4)
                Text("kcal").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(Mono.label)
            }
            Spacer(minLength: 0)
            Button("Save") { onSave(sex, activity); dismiss() }.buttonStyle(.bentoPrimary)
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .glassSheetBackground()
        .presentationCornerRadius(Bento.radius)
    }
}

#if DEBUG
#Preview("Profile") {
    ProfileView()
        .background { AppBackdrop().ignoresSafeArea() }
        .modelContainer(VitalisPreviewData.container)
        .preferredColorScheme(.dark)
}
#endif

// MARK: - ═══ Goals ═══

// MARK: - Day status

/// How a day went against the calorie goal: on target is 85–110% of it (the same band as Home's date wheel).
enum DayGoal {
    case onTarget, offTarget, none

    init(kcal: Double, goal: Double) {
        guard kcal > 0, goal > 0 else { self = .none; return }
        self = (0.85...1.1).contains(kcal / goal) ? .onTarget : .offTarget
    }

    var dot: Color {
        switch self {
        case .onTarget: .ncMoss
        case .offTarget: .ncEmber
        case .none: .clear
        }
    }

    var spoken: String {
        switch self {
        case .onTarget: "calorie goal hit"
        case .offTarget: "logged, off target"
        case .none: "nothing logged"
        }
    }
}

enum MonthMath {
    static var cal: Calendar { Calendar.current }

    static func start(of date: Date) -> Date { cal.dateInterval(of: .month, for: date)?.start ?? cal.startOfDay(for: date) }

    static func adding(_ months: Int, to month: Date) -> Date {
        cal.date(byAdding: .month, value: months, to: month) ?? month
    }

    static func days(in month: Date) -> [Date] {
        let count = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        return (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: month) }
    }

    /// Empty cells before the 1st so it falls under its weekday.
    static func leadingBlanks(_ month: Date) -> Int {
        (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7
    }

    /// One-letter weekday headings in the locale's order (M T W T F S S, or S M T … where weeks start on Sunday).
    static var weekdaySymbols: [String] {
        let s = cal.veryShortWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }
}

// MARK: - Month grid

/// One month as a grid: weekday letters, then each day's number with a dot under it — Moss when the calorie goal was
/// hit, Ember when food was logged but off target, none when nothing was logged. Today sits in a white circle; days
/// still to come are faint. Reads only that month's meals.
struct MonthCalendar: View {
    let month: Date
    let goal: Double
    var large = false
    @Query private var meals: [MealEntry]

    init(month: Date, goal: Double, large: Bool = false) {
        self.month = month
        self.goal = goal
        self.large = large
        let start = month, end = MonthMath.adding(1, to: month)
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start && $0.date < end })
    }

    private var kcalByDay: [Date: Double] {
        var out: [Date: Double] = [:]
        for meal in meals { out[MonthMath.cal.startOfDay(for: meal.date), default: 0] += meal.calories }
        return out
    }

    var body: some View {
        let byDay = kcalByDay
        let today = MonthMath.cal.startOfDay(for: .now)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        VStack(spacing: large ? 10 : 6) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(MonthMath.weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.mono(large ? 11 : 9, .semibold)).foregroundColor(Mono.label)
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: columns, spacing: large ? 8 : 3) {
                ForEach(0..<MonthMath.leadingBlanks(month), id: \.self) { _ in Color.clear.frame(height: 1) }
                ForEach(MonthMath.days(in: month), id: \.self) { day in
                    cell(day, status: DayGoal(kcal: byDay[day] ?? 0, goal: goal), today: day == today, future: day > today)
                }
            }
        }
    }

    private func cell(_ day: Date, status: DayGoal, today: Bool, future: Bool) -> some View {
        let n = MonthMath.cal.component(.day, from: day)
        let size: CGFloat = large ? 34 : 20
        return VStack(spacing: large ? 3 : 1) {
            Text("\(n)")
                .font(large ? .ui(size: 15, weight: today ? .bold : .medium) : .mono(10, today ? .semibold : .medium))
                .monospacedDigit()
                .foregroundColor(today ? Mono.onWhite : Mono.text.opacity(future ? 0.3 : 0.9))
                .frame(width: size, height: size)
                .background { if today { Circle().fill(Mono.text) } }
            Circle().fill(status.dot).frame(width: large ? 6 : 4, height: large ? 6 : 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(today ? "today, \(status.spoken)" : status.spoken)
    }
}

/// The month name with previous / next buttons.
struct MonthSwitcher: View {
    @Binding var month: Date
    var large = false

    var body: some View {
        HStack(spacing: 4) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(large ? .ui(size: 17, weight: .semibold) : .ui(size: 14, weight: .semibold))
                .foregroundColor(Mono.text)
                .contentTransition(.opacity)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            step(-1, "chevron.left", "Previous month")
            step(1, "chevron.right", "Next month")
        }
    }

    private func step(_ by: Int, _ icon: String, _ label: String) -> some View {
        Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { month = MonthMath.adding(by, to: month) }
        } label: {
            Image(systemName: icon).font(.ui(size: 12, weight: .semibold)).foregroundColor(Mono.text)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

extension View {
    /// Swipe left / right to move a month; the grid slides in from the side it came from.
    func monthSwipe(_ month: Binding<Date>) -> some View {
        gesture(DragGesture(minimumDistance: 24).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 40
            else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                month.wrappedValue = MonthMath.adding(value.translation.width < 0 ? 1 : -1, to: month.wrappedValue)
            }
        })
    }
}

// MARK: - Goals page

/// Looks up the profile itself, so the pushed page never depends on the Profile tab's copy.
struct GoalsDestination: View {
    let month: Date
    @Query private var profiles: [UserProfile]

    var body: some View {
        if let profile = profiles.first {
            GoalsView(profile: profile, month: month)
        } else {
            Text("Set up your profile to see your goals.").font(.bentoBody).foregroundColor(Mono.label)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { AppBackdrop().ignoresSafeArea() }
        }
    }
}

/// Everything about your goals: a large month calendar (switch months with the arrows or a swipe), how the month
/// went (days on target, current streak, average intake), and each daily goal.
struct GoalsView: View {
    let profile: UserProfile
    @State var month: Date
    @State private var forward = true
    @AppStorage(RawSettings.sunGoalKey) private var sunGoal = 30
    @Query private var recent: [MealEntry]

    init(profile: UserProfile, month: Date) {
        self.profile = profile
        _month = State(initialValue: month)
        let start = Calendar.current.date(byAdding: .day, value: -180, to: Calendar.current.startOfDay(for: .now)) ?? .now
        _recent = Query(filter: #Predicate<MealEntry> { $0.date >= start })
    }

    private var goals: NutrientGoals { NutrientGoals.from(profile) }

    /// Consecutive days on target, ending yesterday (or today, once today is on target).
    private var streak: Int {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for m in recent { byDay[cal.startOfDay(for: m.date), default: 0] += m.calories }
        var day = cal.startOfDay(for: .now)
        if DayGoal(kcal: byDay[day] ?? 0, goal: goals.calories) != .onTarget {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var n = 0
        while DayGoal(kcal: byDay[day] ?? 0, goal: goals.calories) == .onTarget {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Bento.gap) {
                Text("Goals").font(.bentoTitle).foregroundColor(Mono.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 12) {
                    MonthSwitcher(month: $month, large: true)
                    MonthCalendar(month: month, goal: goals.calories, large: true)
                        .id(month)
                        .transition(.push(from: forward ? .trailing : .leading))
                        .monthSwipe($month)
                    HStack(spacing: 16) {
                        legend(.ncMoss, "Calorie goal hit")
                        legend(.ncEmber, "Off target")
                    }
                    .padding(.top, 4)
                }
                .clipped()
                .bentoTile(padding: 18)

                MonthSummary(month: month, goal: goals.calories, streak: streak)

                dailyGoals
            }
            .padding(.horizontal, Bento.margin)
            .padding(.bottom, 120)
        }
        .glassLightFollowsScroll()
        .background { AppBackdrop().ignoresSafeArea() }
        .onChange(of: month) { old, new in forward = new > old }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.mono(11)).tracking(0.6).textCase(.uppercase).foregroundColor(Mono.label)
        }
    }

    /// Each daily goal with where it comes from.
    private var dailyGoals: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Daily goals").font(.bentoLabel).foregroundColor(Mono.label).padding(.bottom, 4)
            goalRow("flame", "Energy", "\(Int(goals.calories).formatted()) kcal", first: true)
            goalRow("bolt", "Protein", "\(Int(goals.protein)) g")
            goalRow("leaf", "Carbs", "\(Int(goals.carbohydrates)) g")
            goalRow("drop.halffull", "Fat", "\(Int(goals.fat)) g")
            goalRow("circle.grid.cross", "Fiber", "\(Int(goals.fiber)) g")
            goalRow("drop", "Water", String(format: "%.1f L", WaterSheet.goalMl / 1000))
            goalRow("sun.max", "Time outside", "\(sunGoal) min")
            goalRow("scalemass", "Goal weight",
                    "\(Int(profile.goalWeightKg)) kg · now \(Int(profile.weightKg)) kg")
            Text("Energy and macros come from your weight, height, age and activity; edit them on Profile.")
                .font(.ui(size: 12)).foregroundColor(Mono.label)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .bentoTile(padding: 18, art: .sprig)
    }

    private func goalRow(_ icon: String, _ title: String, _ value: String, first: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.ui(size: 14, weight: .medium)).foregroundColor(Mono.text)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            Text(title).font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
            Spacer(minLength: 8)
            Text(value).font(.mono(12)).foregroundColor(Mono.text).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(minHeight: 52)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// How the shown month went: days on target out of days logged, the current streak, and the average intake on
/// logged days against the goal.
private struct MonthSummary: View {
    let month: Date
    let goal: Double
    let streak: Int
    @Query private var meals: [MealEntry]

    init(month: Date, goal: Double, streak: Int) {
        self.month = month
        self.goal = goal
        self.streak = streak
        let start = month, end = MonthMath.adding(1, to: month)
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start && $0.date < end })
    }

    var body: some View {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for m in meals { byDay[cal.startOfDay(for: m.date), default: 0] += m.calories }
        let logged = byDay.count
        let onTarget = byDay.values.filter { DayGoal(kcal: $0, goal: goal) == .onTarget }.count
        let average = logged > 0 ? byDay.values.reduce(0, +) / Double(logged) : 0

        return VStack(spacing: Bento.gap) {
            BentoPair {
                stat("On target", "\(onTarget)", "of \(logged) days logged")
            } right: {
                stat("Streak", "\(streak)", streak == 1 ? "day in a row" : "days in a row")
            }
            stat("Average intake", logged > 0 ? Int(average).formatted() : "—",
                 logged > 0 ? "kcal on logged days · goal \(Int(goal).formatted())" : "Nothing logged this month",
                 progress: goal > 0 ? average / goal : 0)
        }
    }

    private func stat(_ label: String, _ value: String, _ detail: String, progress: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.bentoLabel).foregroundColor(Mono.label)
            Text(value).font(.display(34)).foregroundColor(Mono.text)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(detail).font(.ui(size: 12)).foregroundColor(Mono.label)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            if let progress { BentoBar(value: progress) }
        }
        .bentoTile(padding: 16)
        .accessibilityElement(children: .combine)
    }
}
