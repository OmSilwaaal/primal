import SwiftUI
import SwiftData
import Charts

enum ProfileRoute: Hashable { case settings, goals }

/// The Profile tab, as Liquid Glass over a dark base with slow coloured glows:
/// 1. Header: glass avatar with your initial, your name and membership, and Settings.
/// 2. Bento cluster in one clear-glass holder: Daily energy (lime glass, the last three meals as glossy bubbles), and a
///    2×2 of add food, the meal-photo stack (+N), the rune (streak and insights) and the latest meal with today's
///    count.
/// 3. Details card: weight, height, age, activity (tap one to change it), expanding with More info.
/// 4. Greeting, then the ask bar: ask about what you've logged, or jump to Scan.
/// Raw, Sun and Friends stay reachable at the bottom; Pro, legal and signing out live in Settings.
struct ProfileView: View {
    enum Sheet: Identifiable {
        case editHeight, editAge, editGoal, weight, plan, ask, addFood, addWater, addSun
        var id: Self { self }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var profiles: [UserProfile]
    @Query(sort: \BiomarkerReading.date) private var readings: [BiomarkerReading]
    @Query private var recentMeals: [MealEntry]
    @StateObject private var social = SocialService.shared
    @StateObject private var subscription = SubscriptionManager.shared

    @State private var route: ProfileRoute?
    @State private var pushed: SecondaryScreen?
    @State private var sheet: Sheet?
    /// Log, Week, History and Trends open as edge-to-edge bottom panels.
    @State private var panel: Panel?
    enum Panel { case log, energy, history, info }
    @State private var showScan = false
    @State private var expanded = false
    /// The extra stats' natural height, measured, so the panel can open to exactly that.
    @State private var extraHeight: CGFloat = 0
    @Namespace private var glassSpace

    init() {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: .now)) ?? .now
        _recentMeals = Query(filter: #Predicate<MealEntry> { $0.date >= start }, sort: \MealEntry.date, order: .reverse)
    }

    private var profile: UserProfile? { profiles.first }

    static let activities: [(String, String)] = [
        ("sedentary", "Sedentary"), ("light", "Light"), ("moderate", "Moderate"), ("active", "Active"), ("veryActive", "Very active"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header.padding(.top, 4)
                    if let profile {
                        bento(profile)
                        details(profile)
                    } else {
                        setUp
                    }
                }
                .padding(.horizontal, Bento.margin)
                .padding(.bottom, 210)   // clears the ask bar and the floating tab bar
            }
            .glassLightFollowsScroll()
            // The ask bar rides just above the tab bar, fixed in place while the page scrolls.
            .overlay(alignment: .bottom) {
                if profile != nil {
                    askBar
                        .padding(.horizontal, 14)
                        .padding(.bottom, 80)   // the tab bar is 62 pt tall, 8 pt off the bottom
                }
            }
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
            .sheet(item: $sheet) { sheet in sheetContent(sheet) }
            .bottomPanel(isPresented: Binding(get: { panel != nil }, set: { if !$0 { panel = nil } }),
                         fraction: panel == .log ? 0.52 : 0.62) {
                if let profile { panelContent(profile) }
            }
            .fullScreenCover(isPresented: $showScan) { CameraView(onClose: { showScan = false }) }
        }
        // While Settings or Goals is pushed, its own back-swipe owns the left edge, not page swiping.
        .preference(key: ShowsPushedScreenKey.self, value: route != nil || pushed != nil)
    }

    private func displayName(_ profile: UserProfile?) -> String {
        if let name = social.myProfile?.name, !name.isEmpty { return name }
        if let name = profile?.name, !name.isEmpty { return name }
        return "Friend"
    }

    // MARK: - Header

    private var header: some View {
        let name = displayName(profile)
        return HStack(spacing: 12) {
            Text(String(name.prefix(1)).uppercased())
                .font(.ui(size: 18, weight: .bold)).foregroundColor(.white)
                .frame(width: 50, height: 50)
                .vitalisGlass(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.ui(size: 15, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                Text(subscription.isSubscribed ? "Vitalis Pro member" : "Vitalis member")
                    .font(.ui(size: 13)).foregroundColor(.white.opacity(0.75))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { route = .settings } label: {
                Image(systemName: "gearshape").font(.ui(size: 18, weight: .medium)).foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .vitalisGlass(Circle(), interactive: true)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Bento cluster

    private func bento(_ profile: UserProfile) -> some View {
        let week = weekMeals
        let average = Self.dailyAverage(week)
        let latestPhoto = week.first(where: { $0.photoData != nil })?.photoData

        return GlassGroup(spacing: 4) {
            FlexRow(ratios: [1.1, 1], spacing: 10) {
                // This week's energy. (Today's is Home's ring; this is the 7-day average against the target.)
                Button { panel = .energy } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Week").font(.ui(size: 17, weight: .medium)).foregroundColor(.white.opacity(0.85))
                        TileRing(eaten: average, goal: profile.dailyCalorieGoal, caption: "a day · of")
                            .frame(maxWidth: .infinity)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // The landing page's line drawings: the sprig rising out of the corner.
                    .background(alignment: .bottomTrailing) {
                        Image(LineArt.sprig.rawValue).resizable().scaledToFit()
                            .frame(width: 104, height: 104)
                            .opacity(0.25)   // faint, so the ring stays the focus
                            .offset(x: 18, y: 22)
                            .accessibilityHidden(true)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .vitalisGlass(RoundedRectangle(cornerRadius: 30, style: .continuous), tint: .vitalisLime, interactive: true)
                    .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("This week, \(Int(average)) kilocalories a day on average, of \(Int(profile.dailyCalorieGoal))")
                .accessibilityHint("Opens this week's energy")

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        smallTile(tint: nil, label: "Log", action: { panel = .log }) {
                            tileFace(icon: "square.and.pencil", title: "Log")
                        }
                        smallTile(tint: Color(hex: "#E0A458"), label: "Trends, last 7 days", action: { panel = .info }) {
                            tileFace(icon: "chart.line.uptrend.xyaxis", title: "Trends")
                        }
                    }
                    HStack(spacing: 10) {
                        smallTile(tint: Color(hex: "#0A0B0A"), label: "Goals this month", action: { route = .goals }) {
                            MiniGoalsMonth(meals: recentMeals, goal: profile.dailyCalorieGoal)
                                .padding(10)
                        }
                        smallTile(tint: Color(hex: "#6E9A5B"), photo: latestPhoto,
                                  label: "History, \(week.count) meals in the last 7 days", action: { panel = .history }) {
                            ZStack {
                                tileFace(icon: "clock.arrow.circlepath", title: "History")
                                Text("\(week.count)").font(.ui(size: 12, weight: .bold)).foregroundColor(.white)
                                    .frame(minWidth: 22, minHeight: 22)
                                    .padding(.horizontal, 3)
                                    .vitalisGlass(Capsule(), tint: .ncEmber)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                                    .padding(7)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .vitalisGlass(RoundedRectangle(cornerRadius: 38, style: .continuous), holder: true)
        }
        // No moving light on these tiles: they stay calm and static while the cluster tilts.
        .environment(\.vitalisUnlit, true)
        // Turns in 3D with the phone, like the Vitalis card (gentler, being bigger).
        .tiltsWithPhone(roll: 9, pitch: 7)
    }

    /// A small tile's face: an icon over its name, centred, so no tile is ever blank.
    private func tileFace(icon: String, title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.ui(size: 19, weight: .medium)).foregroundColor(.white.opacity(0.92))
            Text(title).font(.ui(size: 12, weight: .semibold)).foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .accessibilityHidden(true)
    }

    private func smallTile<Content: View>(tint: Color?, photo: Data? = nil, label: String,
                                          action: @escaping () -> Void,
                                          @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return Button(action: action) {
            content()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 80)
                .aspectRatio(1, contentMode: .fit)
                .background {
                    if let photo, let image = UIImage(data: photo) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .opacity(0.55)
                            .clipShape(shape)
                    }
                }
                .vitalisGlass(shape, tint: tint, interactive: true)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 0, maxWidth: .infinity)   // the four small tiles always share the width equally
        .accessibilityLabel(label)
    }

    // MARK: - Details

    /// Body stats as capsules, like the Body tab before: a small label over the value in dot-matrix numerals with
    /// its unit and a faint glow. Weight, height, age and goal first; More info adds BMI, daily energy, activity and
    /// sex. Tap one to change it.
    private func details(_ profile: UserProfile) -> some View {
        let activity = Self.activities.first { $0.0 == profile.activityLevel }?.1 ?? profile.activityLevel
        let bmi = profile.heightCm > 0 ? profile.weightKg / pow(profile.heightCm / 100, 2) : 0
        return VStack(spacing: 10) {
            pair {
                statCapsule("Weight", NutrientRow.dec(profile.weightKg), "kg", glow: .vitalisLime) { sheet = .weight }
            } right: {
                statCapsule("Height", "\(Int(profile.heightCm))", "cm", glow: .ncPrimary) { sheet = .editHeight }
            }
            pair {
                statCapsule("Age", "\(profile.age)", "yrs", glow: .ncPrimary) { sheet = .editAge }
            } right: {
                statCapsule("Goal", NutrientRow.dec(profile.goalWeightKg), "kg", glow: .ncMoss) { sheet = .editGoal }
            }
            // The extra stats sit in a clipped panel whose height opens and closes, so nothing below ever overlaps
            // them mid-animation.
            VStack(spacing: 10) {
                    pair {
                        statCapsule("BMI", bmi > 0 ? String(format: "%.1f", bmi) : "-", "", glow: .ncPrimary, action: nil)
                    } right: {
                        statCapsule("Daily", "\(Int(profile.dailyCalorieGoal))", "kcal", glow: .ncEmber) { panel = .energy }
                    }
                    pair {
                        wordCapsule("Activity", activity) { sheet = .plan }
                    } right: {
                        wordCapsule("Sex", profile.isMale ? "Male" : "Female") { sheet = .plan }
                    }
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { extraHeight = $0 }
            .frame(height: expanded ? extraHeight : 0, alignment: .top)
            .opacity(expanded ? 1 : 0)
            .clipped()
            .padding(.top, expanded ? 0 : -10)   // no extra gap while closed
            .allowsHitTesting(expanded)
            .accessibilityHidden(!expanded)

            Button {
                Haptics.tap()
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.38)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(expanded ? "Less info" : "More info").font(.ui(size: 15, weight: .medium))
                    Image(systemName: "chevron.down").font(.ui(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .vitalisGlass(Capsule(), interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Hides the extra body details" : "Shows the rest of your body details")
        }
    }

    /// Two equal capsules side by side; stacked at accessibility text sizes.
    @ViewBuilder private func pair<L: View, R: View>(@ViewBuilder _ left: () -> L, @ViewBuilder right: () -> R) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { left(); right() }.fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) { left(); right() }
        }
    }

    /// An 84 pt capsule: label, dot-matrix value and mono unit, with a faint glow at the top left.
    private func statCapsule(_ label: String, _ value: String, _ unit: String, glow: Color,
                             action: (() -> Void)?) -> some View {
        capsule(label: label, glow: glow, action: action, spoken: "\(value) \(unit)") {
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                DotMatrixText(text: value, pitch: 3.4).bloom()
                if !unit.isEmpty {
                    Text(unit).font(.mono(11, .semibold)).tracking(0.66).textCase(.uppercase)
                        .foregroundColor(.white.opacity(0.72))
                }
            }
        }
    }

    /// The same capsule for a word value (activity, sex).
    private func wordCapsule(_ label: String, _ value: String, action: @escaping () -> Void) -> some View {
        capsule(label: label, glow: .ncPrimary, action: action, spoken: value) {
            Text(value).font(.ui(size: 17, weight: .semibold)).foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func capsule<V: View>(label: String, glow: Color, action: (() -> Void)?, spoken: String,
                                  @ViewBuilder value: () -> V) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.ui(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.72)).lineLimit(1)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .frame(minHeight: 84)
        .background {
            RadialGradient(colors: [glow.opacity(0.18), .clear], center: .topLeading, startRadius: 0, endRadius: 140)
                .clipShape(Capsule())
        }
        .vitalisGlass(Capsule(), interactive: action != nil)
        .contentShape(Capsule())
        return Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
                    .accessibilityHint("Changes \(label.lowercased())")
            } else {
                content
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
    }

    // MARK: - Ask

    private var askBar: some View {
        GlassGroup(spacing: 4) {
            HStack(spacing: 10) {
                Button { sheet = .ask } label: {
                    HStack(spacing: 10) {
                        Text("Ask").font(.ui(size: 13, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 12).frame(minHeight: 32)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                        Text("What has the most iron?").font(.ui(size: 15)).foregroundColor(.white.opacity(0.78))
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask about your food")
                .accessibilityHint("Opens a question about what you've logged")

                Button { showScan = true } label: {
                    Image(systemName: "viewfinder").font(.ui(size: 17, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan food")
            }
            .padding(.leading, 8).padding(.trailing, 7)
            .frame(minHeight: 58)
            .vitalisGlass(Capsule(), interactive: true, dark: true)
        }
    }

    // MARK: - No profile and More

    private var setUp: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up your profile so your targets can be worked out for you.")
                .font(.ui(size: 15)).foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(destination: ProfileSetupView()) { Text("Set up profile") }
                .buttonStyle(.bentoPrimary)
        }
        .padding(18)
        .vitalisGlass(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    // MARK: - Sheets

    @ViewBuilder private func panelContent(_ profile: UserProfile) -> some View {
        switch panel {
        case .log:
            AddMenuSheet { choice in
                panel = nil
                switch choice {
                case .food: sheet = .addFood
                case .scan: showScan = true
                case .water: sheet = .addWater
                case .sun: sheet = .addSun
                case .weight: sheet = .weight
                }
            }
        case .energy:
            WeekEnergySheet(profile: profile, meals: weekMeals, days: Self.lastSevenDays)
        case .history:
            MealHistorySheet(meals: weekMeals, days: Self.lastSevenDays)
        case .info:
            TrendsSheet(profile: profile, meals: weekMeals, waterMl: weekWaterMl() / 7, sunMinutes: weekSunMinutes() / 7,
                        sunGoal: sunGoal)
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder private func sheetContent(_ sheet: Sheet) -> some View {
        if let profile {
            switch sheet {
            case .editHeight:
                StatEditor(title: "Height", unit: "cm", range: 120...220, step: 1, major: 10, value: profile.heightCm) {
                    profile.heightCm = $0; save("Height saved")
                }
            case .editAge:
                StatEditor(title: "Age", unit: "yrs", range: 13...100, step: 1, major: 5, value: Double(profile.age)) {
                    profile.age = Int($0); save("Age saved")
                }
            case .editGoal:
                StatEditor(title: "Goal weight", unit: "kg", range: 30...200, step: 1, major: 10, value: profile.goalWeightKg.rounded()) {
                    profile.goalWeightKg = $0; save("Goal saved")
                }
            case .weight:
                WeightTrendSheet(current: profile.weightKg, goal: profile.goalWeightKg,
                                 logs: readings.filter { $0.kind == BiomarkerKind.weight.rawValue }) { kg in
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
            case .ask:
                AskSheet(meals: recentMeals)
            case .addFood:
                SearchView(onClose: { self.sheet = nil })
            case .addWater:
                WaterSheet(drinksMl: todayWaterMl(), foodMl: FoodWater.millilitres(in: todaysMeals)) { ml in addWater(ml) }
            case .addSun:
                SunSheet(minutes: todaySunMinutes(), goal: sunGoal) { minutes in addSun(minutes) }
            }
        }
    }

    @AppStorage(RawSettings.sunGoalKey) private var sunGoal = 30

    private var todaysMeals: [MealEntry] { recentMeals.filter { Calendar.current.isDateInToday($0.date) } }

    /// The last seven days, oldest first, ending today.
    static var lastSevenDays: [Date] {
        let cal = Calendar.current, today = cal.startOfDay(for: .now)
        return (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
    }

    /// Meals from the last seven days, newest first.
    private var weekMeals: [MealEntry] {
        let start = Self.lastSevenDays.first ?? .now
        return recentMeals.filter { $0.date >= start }
    }

    /// Average kcal a day over the days that have something logged (empty days would read as fasting).
    static func dailyAverage(_ meals: [MealEntry]) -> Double {
        let days = Set(meals.map { Calendar.current.startOfDay(for: $0.date) }).count
        return days > 0 ? meals.totalCalories / Double(days) : 0
    }

    private func weekWaterMl() -> Double {
        let start = Self.lastSevenDays.first ?? .now
        let days = (try? modelContext.fetch(FetchDescriptor<DailyHydration>(predicate: #Predicate { $0.date >= start }))) ?? []
        return days.reduce(0) { $0 + $1.waterOunces } * WaterSheet.mlPerOunce
    }

    private func weekSunMinutes() -> Double {
        let start = Self.lastSevenDays.first ?? .now
        let sessions = (try? modelContext.fetch(FetchDescriptor<SunSession>(predicate: #Predicate { $0.start >= start }))) ?? []
        return sessions.reduce(0) { $0 + $1.minutes }
    }

    private func todayHydration() -> DailyHydration {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? .now
        let found = try? modelContext.fetch(FetchDescriptor<DailyHydration>(predicate: #Predicate { $0.date >= start && $0.date < end }))
        if let first = found?.first { return first }
        let new = DailyHydration()
        modelContext.insert(new)
        return new
    }

    private func todayWaterMl() -> Double { todayHydration().waterOunces * WaterSheet.mlPerOunce }

    private func todaySunMinutes() -> Double {
        let start = Calendar.current.startOfDay(for: .now)
        let sessions = (try? modelContext.fetch(FetchDescriptor<SunSession>(predicate: #Predicate { $0.start >= start }))) ?? []
        return sessions.reduce(0) { $0 + $1.minutes }
    }

    private func addWater(_ ml: Double) {
        let ounces = ml / WaterSheet.mlPerOunce
        todayHydration().waterOunces += ounces
        HealthKitManager.shared.saveDietaryWater(ounces: ounces)
        try? modelContext.save()
        Haptics.success()
        ToastCenter.shared.show("Added \(Int(ml)) ml water", branded: true)
    }

    private func addSun(_ minutes: Double) {
        let session = SunSession()
        session.start = .now
        session.minutes = minutes
        session.source = "manual"
        modelContext.insert(session)
        try? modelContext.save()
        Haptics.success()
        ToastCenter.shared.show("Added \(Int(minutes)) min outside", branded: true)
    }

    private func save(_ message: String) {
        try? modelContext.save()
        Haptics.success()
        ToastCenter.shared.show(message)
    }
}

// MARK: - Liquid Glass

extension EnvironmentValues {
    /// Turns off the moving light on Vitalis glass inside (the Profile bento keeps still glass).
    @Entry var vitalisUnlit = false
}

extension Color {
    static let vitalisLime = Color(hex: "#D7F25A")
}

extension View {
    /// A slight bloom on numbers: a soft white glow that adds light (plus-lighter), so behind Liquid Glass it lifts
    /// the glass around the digits rather than sitting on top as a flat shadow. Off under Reduce Transparency.
    func bloom(_ radius: CGFloat = 6, strength: Double = 0.55) -> some View {
        modifier(Bloom(radius: radius, strength: strength))
    }
}

private struct Bloom: ViewModifier {
    let radius: CGFloat
    let strength: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
        } else {
            content
                .background {
                    content.blur(radius: radius).opacity(strength).blendMode(.plusLighter)
                        .accessibilityHidden(true)
                }
                .shadow(color: .white.opacity(0.18 * strength), radius: radius * 1.6)
        }
    }
}

/// Native Liquid Glass on iOS 26 (tinted, clear, interactive on tappable shapes); ultra-thin material with a thin
/// white highlight before; a solid dark surface under Reduce Transparency. `holder` is the clear frame around a
/// group of glass tiles: drawn see-through, so the tiles inside it keep their own edges instead of merging into it.
private struct VitalisGlass<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive = false
    var holder = false
    /// Dark, unlit glass for controls that need contrast (the ask bar): an ink tint and no moving light.
    var dark = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.vitalisUnlit) private var unlit

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(shape.fill(Color(hex: "#141614")))
                .overlay(shape.stroke(Color.white.opacity(contrast == .increased ? 0.5 : 0.14), lineWidth: 1))
        } else if holder {
            content
                .background(shape.fill(Color.white.opacity(0.03)))
                .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 1))
        } else if dark {
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.tint(Color.black.opacity(0.55)).interactive(interactive), in: shape)
            } else {
                content
                    .background(shape.fill(Color.black.opacity(0.5)))
                    .background(shape.fill(.ultraThinMaterial))
                    .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .environment(\.colorScheme, .dark)
            }
        } else if #available(iOS 26.0, *) {
            // The moving light caught inside the glass, behind the content (none where unlit).
            content.glassSheen(in: shape, strength: unlit ? 0 : 0.9).glassEffect(glass, in: shape)
        } else {
            content
                .glassSheen(in: shape, strength: unlit ? 0 : 0.9)
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill((tint ?? .clear).opacity(0.25)))
                .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .environment(\.colorScheme, .dark)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        let base: Glass = tint.map { Glass.regular.tint($0.opacity(0.32)) } ?? .clear
        return base.interactive(interactive)
    }
}

private extension View {
    func vitalisGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false, holder: Bool = false,
                                dark: Bool = false) -> some View {
        modifier(VitalisGlass(shape: shape, tint: tint, interactive: interactive, holder: holder, dark: dark))
    }

    /// Lets a glass shape morph as it changes (iOS 26), unless Reduce Motion is on.
    @ViewBuilder func vitalisGlassID(_ id: String, in ns: Namespace.ID) -> some View {
        if #available(iOS 26.0, *), !UIAccessibility.isReduceMotionEnabled {
            glassEffectID(id, in: ns)
        } else {
            self
        }
    }
}

/// Home's calorie ring at tile size: gray track, white arc, the kcal with the target under it.
private struct TileRing: View {
    let eaten: Double
    let goal: Double
    var caption = "of"
    private let size: CGFloat = 112
    private let width: CGFloat = 10

    var body: some View {
        let progress = goal > 0 ? eaten / goal : 0
        ZStack {
            Circle().stroke(Color.white.opacity(0.22), lineWidth: width)
            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(Color.white, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.6), value: progress)
            VStack(spacing: 0) {
                AlgizMark().fill(Color.white.opacity(progress >= 1 ? 1 : 0.5)).frame(width: 8, height: 10)
                    .padding(.bottom, 3)
                Text(Int(eaten).formatted()).font(.bentoNumber(26)).tracking(Font.bentoTracking(26))
                    .foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text("\(caption) \(Int(goal).formatted())").font(.ui(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.8))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, width + 8)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// This month at a glance in a small tile: a tiny dot per day (Moss on target, Ember off target, faint when nothing
/// was logged, white for today) under a small "Goals" label.
private struct MiniGoalsMonth: View {
    let meals: [MealEntry]
    let goal: Double

    var body: some View {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for m in meals { byDay[cal.startOfDay(for: m.date), default: 0] += m.calories }
        let month = MonthMath.start(of: .now)
        let today = cal.startOfDay(for: .now)
        let blanks = MonthMath.leadingBlanks(month)
        let days = MonthMath.days(in: month)
        let onTarget = days.filter { DayGoal(kcal: byDay[$0] ?? 0, goal: goal) == .onTarget }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                AlgizMark().fill(Color.vitalisLime).frame(width: 7, height: 9)
                Text("Goals").font(.ui(size: 11, weight: .semibold)).foregroundColor(.white)
            }
            Spacer(minLength: 0)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(5), spacing: 3), count: 7), alignment: .leading, spacing: 3) {
                ForEach(0..<blanks, id: \.self) { _ in Color.clear.frame(height: 5) }
                ForEach(days, id: \.self) { day in
                    Circle().fill(color(DayGoal(kcal: byDay[day] ?? 0, goal: goal), today: day == today, future: day > today))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Goals this month, \(onTarget) days on target")
    }

    private func color(_ g: DayGoal, today: Bool, future: Bool) -> Color {
        if today { return .white }
        switch g {
        case .onTarget: return .ncMoss
        case .offTarget: return .ncEmber
        case .none: return .white.opacity(future ? 0.12 : 0.28)
        }
    }
}

/// Lays children out side by side in proportion to `ratios`, all at the height of the tallest.
private struct FlexRow: Layout {
    let ratios: [CGFloat]
    var spacing: CGFloat = 10

    private func widths(_ total: CGFloat, count: Int) -> [CGFloat] {
        let r = (0..<count).map { $0 < ratios.count ? ratios[$0] : 1 }
        let sum = r.reduce(0, +)
        let room = max(0, total - spacing * CGFloat(max(0, count - 1)))
        return r.map { room * $0 / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 360
        let ws = widths(total, count: subviews.count)
        let h = zip(subviews, ws).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
        return CGSize(width: total, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let ws = widths(bounds.width, count: subviews.count)
        var x = bounds.minX
        for (view, w) in zip(subviews, ws) {
            view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
}

// MARK: - Add menu

/// What the + tile adds: a meal (search or scan), water, time outside, or today's weight.
private struct AddMenuSheet: View {
    enum Choice { case food, scan, water, sun, weight }
    let onChoose: (Choice) -> Void

    private let items: [(Choice, String, String, String)] = [
        (.food, "fork.knife", "Food", "Search and log a meal"),
        (.scan, "viewfinder", "Scan", "Barcode or a photo of your plate"),
        (.water, "drop", "Water", "A glass or a bottle"),
        (.sun, "sun.max", "Time outside", "Minutes in daylight"),
        (.weight, "scalemass", "Weight", "Today's weigh-in"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Log").font(.ui(size: 22, weight: .bold)).foregroundColor(.white)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                ForEach(items, id: \.2) { choice, icon, title, detail in
                    Button {
                        Haptics.tap()
                        onChoose(choice)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: icon).font(.ui(size: 17, weight: .medium)).foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .vitalisGlass(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(.ui(size: 16, weight: .semibold)).foregroundColor(.white)
                                Text(detail).font(.ui(size: 12)).foregroundColor(.white.opacity(0.72))
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right").font(.ui(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding(.horizontal, 14).frame(minHeight: 60)
                        .vitalisGlass(Capsule(), interactive: true)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .glassSheetBackground()
        .presentationCornerRadius(Bento.radius)
    }
}

/// Trends: the last seven days as daily averages — energy, water, time outside, meals — and the three nutrients
/// that ran lowest across the week. (Today's numbers live on Home and Data; this is the longer view.)
private struct TrendsSheet: View {
    let profile: UserProfile
    let meals: [MealEntry]
    let waterMl: Double
    let sunMinutes: Double
    let sunGoal: Int

    var body: some View {
        let goals = NutrientGoals.from(profile)
        let logged = max(1, Set(meals.map { Calendar.current.startOfDay(for: $0.date) }).count)
        // Each nutrient's average over the days logged, against the daily target.
        let low = buildNutrientList(from: meals, goals: goals)
            .filter { $0.group != .macros }
            .map { NutrientInfo(id: $0.id, name: $0.name, unit: $0.unit, icon: $0.icon, group: $0.group,
                                current: $0.current / Double(logged), goal: $0.goal) }
            .sorted { $0.progress < $1.progress }
            .prefix(3)
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Trends").font(.ui(size: 22, weight: .bold)).foregroundColor(.white)
                    .padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)
                Text("Last 7 days · a day on average").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                    .foregroundColor(.white.opacity(0.72))
                VStack(spacing: 0) {
                    row("flame", "Energy", "\(Int(ProfileView.dailyAverage(meals)).formatted()) of \(Int(goals.calories).formatted()) kcal", first: true)
                    row("drop", "Water", String(format: "%.1f of %.1f L", waterMl / 1000, WaterSheet.goalMl / 1000))
                    row("sun.max", "Time outside", "\(Int(sunMinutes.rounded())) of \(sunGoal) min")
                    row("fork.knife", "Meals", String(format: "%.1f", Double(meals.count) / 7))
                }
                .padding(.horizontal, 16)
                .liquidGlassPanel(in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text("Lowest this week").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(.white.opacity(0.72))
                    .padding(.top, 4)
                VStack(spacing: 0) {
                    if meals.isEmpty {
                        Text("Log a few meals to see what runs low.").font(.ui(size: 15)).foregroundColor(.white.opacity(0.72))
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    }
                    ForEach(Array(low.enumerated()), id: \.element.id) { i, n in
                        row("exclamationmark.circle", n.name, "\(n.percentage)% of target", first: i == 0)
                    }
                }
                .padding(.horizontal, 16)
                .liquidGlassPanel(in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                Text("Food averages count the days you logged; water and time outside count all seven. Targets follow NIH dietary reference intakes for your age and sex.")
                    .font(.ui(size: 12)).foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
    }

    private func row(_ icon: String, _ title: String, _ value: String, first: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.ui(size: 14, weight: .medium)).foregroundColor(.white).frame(width: 22)
            Text(title).font(.ui(size: 15)).foregroundColor(.white.opacity(0.8))
            Spacer(minLength: 8)
            Text(value).font(.ui(size: 15, weight: .medium)).foregroundColor(.white).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 50)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1) } }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Week and History sheets

/// This week's energy: the daily average against the target, a bar per day (Moss on target, Ember off, faint when
/// nothing was logged) under a dashed target line, how many days landed on target, and where the target comes from.
private struct WeekEnergySheet: View {
    let profile: UserProfile
    let meals: [MealEntry]
    let days: [Date]

    var body: some View {
        let goal = NutrientGoals.from(profile).calories
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for m in meals { byDay[cal.startOfDay(for: m.date), default: 0] += m.calories }
        let onTarget = days.filter { DayGoal(kcal: byDay[$0] ?? 0, goal: goal) == .onTarget }.count
        let ceiling = max(goal * 1.3, byDay.values.max() ?? 0)
        let chartHeight: CGFloat = 120

        return VStack(alignment: .leading, spacing: 16) {
            Text("This week").font(.ui(size: 22, weight: .bold)).foregroundColor(.white)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(Int(ProfileView.dailyAverage(meals)).formatted()).font(.display(44)).foregroundColor(.white)
                Text("kcal a day · target \(Int(goal).formatted())").font(.ui(size: 15)).foregroundColor(.white.opacity(0.72))
            }
            .accessibilityElement(children: .combine)

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days, id: \.self) { day in
                    let kcal = byDay[day] ?? 0
                    let status = DayGoal(kcal: kcal, goal: goal)
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(status == .onTarget ? Color.ncMoss : status == .offTarget ? Color.ncEmber : Color.white.opacity(0.18))
                            .frame(height: max(10, chartHeight * kcal / max(ceiling, 1)))
                            .frame(height: chartHeight, alignment: .bottom)
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.mono(10, .semibold))
                            .foregroundColor(cal.isDateInToday(day) ? .white : .white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))), \(Int(kcal)) kilocalories, \(status.spoken)")
                }
            }
            // The target as a dashed line across the bars.
            .overlay(alignment: .bottom) {
                Rectangle()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(height: 1)
                    .padding(.bottom, 16 + chartHeight * goal / max(ceiling, 1))
                    .accessibilityHidden(true)
            }

            Text("\(onTarget) of 7 days on target").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                .foregroundColor(.white.opacity(0.72))
            Text("The target is worked out from your weight, height, age, sex and activity (Mifflin–St Jeor), plus what Apple Health says you've burned on Home. The average counts the days you logged.")
                .font(.ui(size: 13)).foregroundColor(.white.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// History: every meal from the last seven days, grouped by day (newest first) with each day's total. Home shows one
/// day at a time; this is the week in one list.
private struct MealHistorySheet: View {
    let meals: [MealEntry]
    let days: [Date]

    var body: some View {
        let cal = Calendar.current
        let filled = days.reversed().compactMap { day -> (Date, [MealEntry])? in
            let list = meals.filter { cal.isDate($0.date, inSameDayAs: day) }.sorted { $0.date > $1.date }
            return list.isEmpty ? nil : (day, list)
        }
        return VStack(alignment: .leading, spacing: 14) {
            Text("History").font(.ui(size: 22, weight: .bold)).foregroundColor(.white)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            Text("Last 7 days · \(meals.count) meals").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                .foregroundColor(.white.opacity(0.72))
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if filled.isEmpty {
                        Text("Nothing logged in the last 7 days.").font(.ui(size: 15)).foregroundColor(.white.opacity(0.72))
                    }
                    ForEach(filled, id: \.0) { day, list in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(cal.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                    .font(.ui(size: 15, weight: .semibold)).foregroundColor(.white)
                                Spacer()
                                Text("\(Int(list.totalCalories).formatted()) kcal").font(.ui(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.72))
                            }
                            .accessibilityElement(children: .combine)
                            VStack(spacing: 0) {
                                ForEach(Array(list.enumerated()), id: \.element.id) { i, meal in
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(meal.foodName.components(separatedBy: ",").first?.capitalized ?? meal.foodName)
                                                .font(.ui(size: 15, weight: .medium)).foregroundColor(.white).lineLimit(1)
                                            Text("\(MealSlot.name(for: meal.date)) · \(meal.date.formatted(date: .omitted, time: .shortened)) · \(Int(meal.servingSize)) g")
                                                .font(.ui(size: 12)).foregroundColor(.white.opacity(0.65))
                                        }
                                        Spacer(minLength: 8)
                                        Text("\(Int(meal.calories).formatted()) kcal").font(.ui(size: 15, weight: .semibold)).foregroundColor(.white)
                                    }
                                    .frame(minHeight: 56)
                                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1) } }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                            .padding(.horizontal, 16)
                            .liquidGlassPanel(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Ask about what you've logged: name a nutrient ("What has the most iron?") and see the foods from the last 30 days
/// that gave you the most of it per serving. Answers come only from your own log.
private struct AskSheet: View {
    let meals: [MealEntry]
    @State private var question = "What has the most iron?"
    @FocusState private var focused: Bool

    private static let nutrients: [(words: [String], name: String, unit: String, value: (MealEntry) -> Double)] = [
        (["iron"], "Iron", "mg", { $0.iron }),
        (["protein"], "Protein", "g", { $0.protein }),
        (["fat"], "Fat", "g", { $0.totalFat }),
        (["carb"], "Carbs", "g", { $0.carbohydrates }),
        (["fiber", "fibre"], "Fiber", "g", { $0.fiber }),
        (["calorie", "kcal", "energy"], "Energy", "kcal", { $0.calories }),
        (["vitamin a"], "Vitamin A", "mcg", { $0.vitaminA }),
        (["vitamin c"], "Vitamin C", "mg", { $0.vitaminC }),
        (["vitamin d"], "Vitamin D", "mcg", { $0.vitaminD }),
        (["vitamin e"], "Vitamin E", "mg", { $0.vitaminE }),
        (["vitamin k"], "Vitamin K", "mcg", { $0.vitaminK }),
        (["b12"], "Vitamin B12", "mcg", { $0.vitaminB12 }),
        (["folate", "b9"], "Folate", "mcg", { $0.folate }),
        (["calcium"], "Calcium", "mg", { $0.calcium }),
        (["magnesium"], "Magnesium", "mg", { $0.magnesium }),
        (["potassium"], "Potassium", "mg", { $0.potassium }),
        (["zinc"], "Zinc", "mg", { $0.zinc }),
        (["selenium"], "Selenium", "mcg", { $0.selenium }),
        (["copper"], "Copper", "mg", { $0.copper }),
        (["omega", "omega-3"], "Omega-3", "g", { $0.omega3 }),
        (["sodium", "salt"], "Sodium", "mg", { $0.sodium }),
    ]

    private var match: (name: String, unit: String, value: (MealEntry) -> Double)? {
        let q = question.lowercased()
        return Self.nutrients.first { $0.words.contains { q.contains($0) } }.map { ($0.name, $0.unit, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ask").font(.ui(size: 22, weight: .bold)).foregroundColor(.white)
            TextField("Ask about a nutrient", text: $question)
                .font(.ui(size: 15)).foregroundColor(.white)
                .focused($focused)
                .submitLabel(.search)
                .padding(.horizontal, 18).frame(minHeight: 52)
                .vitalisGlass(Capsule())
            if let match {
                answer(match)
            } else {
                Text("Name a nutrient — iron, protein, vitamin D, magnesium — and I'll rank what you've logged.")
                    .font(.ui(size: 14)).foregroundColor(.white.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("Answers come from the meals you've logged in the last 30 days.")
                .font(.ui(size: 12)).foregroundColor(.white.opacity(0.6))
        }
        .padding(22)
        .presentationDetents([.medium, .large])
        .glassSheetBackground()
        .presentationCornerRadius(Bento.radius)
    }

    private func answer(_ m: (name: String, unit: String, value: (MealEntry) -> Double)) -> some View {
        // The best serving of each food.
        var best: [String: Double] = [:]
        for meal in meals {
            let name = meal.foodName.components(separatedBy: ",").first?.capitalized ?? meal.foodName
            best[name] = max(best[name] ?? 0, m.value(meal))
        }
        let top = best.filter { $0.value > 0 }.sorted { $0.value > $1.value }.prefix(5)
        return VStack(alignment: .leading, spacing: 0) {
            if top.isEmpty {
                Text("Nothing you've logged in the last 30 days has \(m.name.lowercased()) recorded yet.")
                    .font(.ui(size: 14)).foregroundColor(.white.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Most \(m.name.lowercased()) per serving").font(.mono(11, .semibold)).tracking(0.88)
                    .textCase(.uppercase).foregroundColor(.white.opacity(0.72)).padding(.bottom, 4)
                ForEach(Array(top.enumerated()), id: \.offset) { i, item in
                    HStack {
                        Text(item.key).font(.ui(size: 15, weight: i == 0 ? .semibold : .regular)).foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("\(NutrientRow.dec(item.value)) \(m.unit)").font(.ui(size: 15, weight: .medium)).foregroundColor(.white)
                    }
                    .frame(minHeight: 46)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1) } }
                    .accessibilityElement(children: .combine)
                }
            }
        }
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

/// Weight over time as a Liquid Glass chart. A smooth line through every logged weight with a soft fill, the goal as
/// a dashed line, and a range switch. Touch and drag across it: a white dot glides from log to log and a glass
/// tooltip shows that day's weight and the change since the start of the range. Above it, the numbers that matter
/// (now, change over the range, weekly pace, left to goal); below it, logging today's weight.
private struct WeightTrendSheet: View {
    struct Log: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let kg: Double
    }

    enum Span: String, CaseIterable, Identifiable {
        case month = "1M", quarter = "3M", half = "6M", year = "1Y", all = "All"
        var id: Self { self }
        var days: Int? {
            switch self {
            case .month: 30
            case .quarter: 91
            case .half: 182
            case .year: 365
            case .all: nil
            }
        }
    }

    let current: Double
    let goal: Double
    let allLogs: [Log]
    let onLog: (Double) -> Void
    @State private var span: Span = .quarter
    @State private var selected: Log?
    /// The slider works in half kilos.
    @State private var halves: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(current: Double, goal: Double, logs: [BiomarkerReading], onLog: @escaping (Double) -> Void) {
        self.current = current
        self.goal = goal
        self.onLog = onLog
        // One point per day (the day's last reading), oldest first.
        var byDay: [Date: BiomarkerReading] = [:]
        for r in logs { byDay[Calendar.current.startOfDay(for: r.date)] = r }
        allLogs = byDay.values.sorted { $0.date < $1.date }.map { Log(id: $0.id, date: $0.date, kg: $0.value) }
        // Start the slider at the latest weigh-in, else the profile's weight.
        let start = allLogs.last?.kg ?? current
        _halves = State(initialValue: min(max((start * 2).rounded(), 60), 500))
    }

    private var logs: [Log] {
        guard let days = span.days, let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) else { return allLogs }
        return allLogs.filter { $0.date >= start }
    }

    private var yDomain: ClosedRange<Double> {
        let values = logs.map(\.kg) + (goal > 0 ? [goal] : [])
        let lo = (values.min() ?? current) - 1, hi = (values.max() ?? current) + 1
        return lo...max(hi, lo + 2)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Weight").font(.ui(size: 22, weight: .bold)).foregroundColor(.white)
                    .padding(.top, 14)
                    .accessibilityAddTraits(.isHeader)
                summary
                chartCard
                logCard
            }
            .padding(20)
        }
        .presentationDetents([.large])
        .glassSheetBackground()
        .presentationCornerRadius(Bento.radius)
    }

    // MARK: Summary

    private var summary: some View {
        let first = logs.first?.kg, last = logs.last?.kg ?? current
        let change = first.map { last - $0 }
        let weeks = logs.count > 1 ? max(1, (logs.last!.date.timeIntervalSince(logs.first!.date)) / (7 * 86_400)) : 0
        let pace = change.map { weeks > 0 ? $0 / weeks : 0 }
        let left = goal > 0 ? last - goal : nil
        return HStack(spacing: 10) {
            stat("Now", String(format: "%.1f", last), "kg")
            stat("Change", change.map { signed($0) } ?? "—", "kg", color: change.map(changeColor))
            stat("Per week", pace.map { signed($0) } ?? "—", "kg")
            stat("To goal", left.map { abs($0) < 0.1 ? "0" : String(format: "%.1f", abs($0)) } ?? "—", "kg")
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.mono(11, .semibold)).tracking(0.5).textCase(.uppercase).foregroundColor(.white.opacity(0.72))
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.display(18)).foregroundColor(color ?? .white).lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.mono(11)).foregroundColor(.white.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .liquidGlassPanel(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Moving towards the goal is good news whichever way the goal lies.
    private func changeColor(_ delta: Double) -> Color {
        guard abs(delta) >= 0.05, goal > 0, let start = logs.first?.kg else { return .white }
        return (goal < start) == (delta < 0) ? .ncMoss : .ncEmber
    }

    private func signed(_ v: Double) -> String { abs(v) < 0.05 ? "0.0" : String(format: "%+.1f", v) }

    // MARK: Chart

    private var chartCard: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            // Range switch.
            HStack(spacing: 4) {
                ForEach(Span.allCases) { s in
                    let on = span == s
                    Button {
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) { span = s; selected = nil }
                    } label: {
                        Text(s.rawValue).font(.mono(11, .semibold))
                            .foregroundColor(on ? Mono.onWhite : .white)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background { if on { Capsule().fill(Color.white) } }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(4)
            .liquidGlassPanel(in: Capsule())

            if logs.count < 2 {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "chart.xyaxis.line").font(.ui(size: 22)).foregroundColor(.white.opacity(0.8))
                    Text(logs.isEmpty ? "No weights logged in this range yet." : "One weight logged in this range.")
                        .font(.ui(size: 15, weight: .semibold)).foregroundColor(.white)
                    Text("Log your weight a few times and your trend appears here. Apple Health weights sync in from Biomarkers.")
                        .font(.ui(size: 13)).foregroundColor(.white.opacity(0.72)).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
            } else {
                chart.frame(height: 240)
                Text(selected == nil ? "Touch and drag along the line to see each weigh-in."
                                     : "Release to clear.")
                    .font(.ui(size: 12)).foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(16)
        .glassSheen(in: shape, strength: 0.8)
        .liquidGlassPanel(in: shape)
    }

    private var chart: some View {
        let first = logs.first?.kg ?? current
        return Chart {
            ForEach(logs) { log in
                AreaMark(x: .value("Date", log.date), yStart: .value("Base", yDomain.lowerBound), yEnd: .value("Weight", log.kg))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", log.date), y: .value("Weight", log.kg))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.white)
                PointMark(x: .value("Date", log.date), y: .value("Weight", log.kg))
                    .symbolSize(selected == log ? 0 : 18)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .accessibilityLabel(log.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(String(format: "%.1f", log.kg)) kilograms")
            }
            if goal > 0, yDomain.contains(goal) {
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.ncMoss.opacity(0.9))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal \(NutrientRow.dec(goal))").font(.mono(11, .semibold)).foregroundColor(.ncMoss)
                    }
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(Color.white.opacity(0.5))
                PointMark(x: .value("Selected", selected.date), y: .value("Weight", selected.kg))
                    .symbol {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.18)).frame(width: 30, height: 30)
                            Circle().fill(Color.white).frame(width: 14, height: 14)
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                        }
                    }
                    .annotation(position: .top, spacing: 10, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(selected, first: first)
                    }
            }
        }
        .chartYScale(domain: yDomain)
        // Room at the ends so the first and last date labels aren't clipped.
        .chartXScale(range: .plotDimension(startPadding: 6, endPadding: 30))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(Color.white.opacity(0.7))
                    .font(.mono(11))
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel().foregroundStyle(Color.white.opacity(0.7)).font(.mono(11))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let plot = proxy.plotFrame else { return }
                            let x = value.location.x - geo[plot].origin.x
                            guard let date: Date = proxy.value(atX: x) else { return }
                            // Snap to the nearest log, so the dot always sits on a real weigh-in.
                            let nearest = logs.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
                            if nearest != selected {
                                Haptics.selection()
                                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) { selected = nearest }
                            }
                        }
                        .onEnded { _ in
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { selected = nil }
                        })
            }
        }
        .accessibilityLabel("Weight chart")
    }

    private func tooltip(_ log: Log, first: Double) -> some View {
        let delta = log.kg - first
        return VStack(alignment: .leading, spacing: 2) {
            Text(log.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(.mono(11, .semibold)).textCase(.uppercase).foregroundColor(.white.opacity(0.75))
            Text("\(String(format: "%.1f", log.kg)) kg").font(.display(17)).foregroundColor(.white)
            Text("\(signed(delta)) kg since start").font(.ui(size: 11, weight: .semibold))
                .foregroundColor(changeColor(delta))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glass(.tinted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fixedSize()
    }

    // MARK: Log

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log today").font(.bentoLabel).foregroundColor(.white.opacity(0.72))
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                DotMatrixText(text: String(format: "%.1f", halves / 2), pitch: 5)
                Text("kg").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase).foregroundColor(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity)
            LineRuler(amount: $halves, range: 60...500, step: 1, major: 10, spokenUnit: "half kilograms") {
                "\($0 / 2)"
            }
            .padding(.horizontal, -16)
            Button("Log \(String(format: "%.1f", halves / 2)) kg") { onLog(halves / 2); dismiss() }
                .buttonStyle(.bentoPrimary)
        }
        .padding(16)
        .liquidGlassPanel(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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

/// One month as a grid: weekday letters, then each day's number with dots under it — first the calorie target (Moss
/// when hit, Ember when food was logged but off target), then one per goal due that day (lime when done, an outline
/// while it isn't). Today sits in a white circle; days still to come are faint. With `selected`, tapping a day picks
/// it and it gets a ring. Reads only that month's meals.
struct MonthCalendar: View {
    let month: Date
    let goal: Double
    var large = false
    var goals: [Goal] = []
    var selected: Binding<Date>? = nil
    @Query private var meals: [MealEntry]

    init(month: Date, goal: Double, large: Bool = false, goals: [Goal] = [], selected: Binding<Date>? = nil) {
        self.month = month
        self.goal = goal
        self.large = large
        self.goals = goals
        self.selected = selected
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

    @ViewBuilder private func cell(_ day: Date, status: DayGoal, today: Bool, future: Bool) -> some View {
        let n = MonthMath.cal.component(.day, from: day)
        let size: CGFloat = large ? 34 : 20
        let due = goals.filter { $0.isDue(on: day) }
        let done = due.filter { $0.isDone(on: day) }.count
        let isSelected = selected.map { MonthMath.cal.isDate($0.wrappedValue, inSameDayAs: day) } ?? false
        let dot: CGFloat = large ? 5 : 4
        let face = VStack(spacing: large ? 4 : 1) {
            Text("\(n)")
                .font(large ? .ui(size: 15, weight: today ? .bold : .medium) : .mono(10, today ? .semibold : .medium))
                .monospacedDigit()
                .foregroundColor(today ? Mono.onWhite : Mono.text.opacity(future ? 0.3 : 0.9))
                .frame(width: size, height: size)
                .background { if today { Circle().fill(Mono.text) } }
                .overlay { if isSelected && !today { Circle().strokeBorder(Mono.text, lineWidth: 1.5) } }
            HStack(spacing: 2) {
                if status != .none { Circle().fill(status.dot).frame(width: dot, height: dot) }
                ForEach(Array(due.prefix(3).enumerated()), id: \.offset) { _, g in
                    if g.isDone(on: day) {
                        Circle().fill(Color.vitalisLime).frame(width: dot, height: dot)
                    } else {
                        Circle().strokeBorder(Color.vitalisLime.opacity(future ? 0.45 : 0.8), lineWidth: 1).frame(width: dot, height: dot)
                    }
                }
            }
            .frame(height: dot)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue((today ? "today, " : "") + status.spoken + (due.isEmpty ? "" : ", \(done) of \(due.count) goals done"))
        if let selected {
            Button {
                Haptics.selection()
                withAnimation(.smooth(duration: 0.25)) { selected.wrappedValue = MonthMath.cal.startOfDay(for: day) }
            } label: { face }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            face
        }
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

/// Your goals on a calendar: a large month (switch months with the arrows or a swipe) where each day shows the
/// calorie target and a dot per goal due, then the chosen day's goals to tick off, and Add goal to set a new one.
struct GoalsView: View {
    let profile: UserProfile
    @State var month: Date
    @State private var forward = true
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var adding = false
    @Query(sort: \Goal.created) private var goals: [Goal]
    @Environment(\.modelContext) private var context

    init(profile: UserProfile, month: Date) {
        self.profile = profile
        _month = State(initialValue: month)
    }

    private var calorieGoal: Double { NutrientGoals.from(profile).calories }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Bento.gap) {
                Text("Goals").font(.bentoTitle).foregroundColor(Mono.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 12) {
                    MonthSwitcher(month: $month, large: true)
                    MonthCalendar(month: month, goal: calorieGoal, large: true, goals: goals, selected: $selected)
                        .id(month)
                        .transition(.push(from: forward ? .trailing : .leading))
                        .monthSwipe($month)
                    HStack(spacing: 14) {
                        legend(Circle().fill(Color.ncMoss), "Calories hit")
                        legend(Circle().fill(Color.vitalisLime), "Goal done")
                        legend(Circle().strokeBorder(Color.vitalisLime, lineWidth: 1), "Goal due")
                    }
                    .padding(.top, 4)
                }
                .clipped()
                .bentoTile(padding: 18)

                dayGoals
            }
            .padding(.horizontal, Bento.margin)
            .padding(.bottom, 120)
        }
        .glassLightFollowsScroll()
        .background { AppBackdrop().ignoresSafeArea() }
        .onChange(of: month) { old, new in forward = new > old }
        .sheet(isPresented: $adding) {
            GoalEditor(day: selected) { goal in
                context.insert(goal)
                try? context.save()
                Haptics.success()
                ToastCenter.shared.show("Goal added", branded: true)
            }
        }
    }

    private func legend(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 6) {
            mark.frame(width: 7, height: 7)
            Text(text).font(.mono(10)).tracking(0.5).textCase(.uppercase).foregroundColor(Mono.label)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: The chosen day

    private var dayGoals: some View {
        let cal = Calendar.current
        let due = goals.filter { $0.isDue(on: selected) }
        let done = due.filter { $0.isDone(on: selected) }.count
        let canTick = selected <= cal.startOfDay(for: .now)
        let title = cal.isDateInToday(selected) ? "Today"
            : selected.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ui(size: 20, weight: .bold)).foregroundColor(Mono.text)
                        .contentTransition(.opacity)
                    Text(due.isEmpty ? "No goals on this day" : "\(done) of \(due.count) done")
                        .font(.bentoLabel).foregroundColor(Mono.label)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button { adding = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.bentoRound)
                    .accessibilityLabel("Add goal")
            }
            .padding(.bottom, due.isEmpty ? 0 : 6)

            ForEach(Array(due.enumerated()), id: \.element.id) { i, goal in
                goalRow(goal, canTick: canTick, first: i == 0)
            }

            if due.isEmpty {
                Button { adding = true } label: {
                    Label("Add a goal", systemImage: "plus")
                        .font(.ui(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bentoPrimary)
                .padding(.top, 14)
                Text("Set it once, every day or on chosen days; it shows on the calendar on each day it's due.")
                    .font(.ui(size: 12)).foregroundColor(Mono.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .bentoTile(padding: 18, art: .sprig)
        .animation(.smooth(duration: 0.25), value: selected)
    }

    private func goalRow(_ goal: Goal, canTick: Bool, first: Bool) -> some View {
        let isDone = goal.isDone(on: selected)
        return HStack(spacing: 12) {
            Image(systemName: goal.icon).font(.ui(size: 14, weight: .medium)).foregroundColor(Mono.text)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title).font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
                    .strikethrough(isDone, color: Mono.text.opacity(0.5))
                    .lineLimit(2)
                Text(goal.scheduleText).font(.ui(size: 12)).foregroundColor(Mono.label).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { goal.toggle(on: selected) }
                try? context.save()
                if !isDone { Haptics.success() }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.ui(size: 24, weight: .regular))
                    .foregroundColor(isDone ? .vitalisLime : Mono.text.opacity(canTick ? 0.7 : 0.25))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canTick)
            .accessibilityLabel(isDone ? "Done" : "Not done")
            .accessibilityHint(canTick ? "Marks \(goal.title) for this day" : "Days still to come can't be ticked yet")
        }
        .frame(minHeight: 58)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                withAnimation(.smooth) { context.delete(goal) }
                try? context.save()
            } label: { Label("Delete goal", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Delete goal") { context.delete(goal); try? context.save() }
    }
}

// MARK: - New goal

/// Set a goal: what it is (or a suggestion), an icon, and when — once on a date, every day, or on chosen weekdays,
/// from a start date with an optional end.
private struct GoalEditor: View {
    let day: Date
    let onSave: (Goal) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Schedule: Hashable { case once, daily, weekdays }

    @State private var title = ""
    @State private var icon = "target"
    @State private var schedule: Schedule = .daily
    @State private var date: Date
    @State private var weekdays: Set<Int> = []
    @State private var hasEnd = false
    @State private var end: Date
    @FocusState private var typing: Bool

    init(day: Date, onSave: @escaping (Goal) -> Void) {
        self.day = day
        self.onSave = onSave
        let start = max(day, Calendar.current.startOfDay(for: .now))
        _date = State(initialValue: start)
        _end = State(initialValue: Calendar.current.date(byAdding: .day, value: 30, to: start) ?? start)
    }

    /// Ideas in the app's spirit: nose-to-tail, raw, outdoors.
    private static let suggestions: [(String, String)] = [
        ("Organ meat", "heart"), ("Raw egg yolks", "circle.circle"), ("Morning sun", "sun.max"),
        ("Bone broth", "flame"), ("No seed oils", "drop.triangle"), ("Walk 30 min", "figure.walk"),
        ("Sleep by 10", "moon"), ("Hit protein", "bolt"),
    ]
    private static let icons = ["target", "heart", "circle.circle", "sun.max", "flame", "drop", "drop.triangle",
                                "leaf", "fish", "figure.walk", "moon", "bolt", "scalemass", "fork.knife"]

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (schedule != .weekdays || !weekdays.isEmpty)
            && (!hasEnd || schedule == .once || end >= date)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("New goal").font(.ui(size: 22, weight: .bold)).foregroundColor(Mono.text)
                    .padding(.top, 20)
                    .accessibilityAddTraits(.isHeader)

                section("Goal") {
                    TextField("", text: $title, prompt: Text("What do you want to do?").foregroundColor(Mono.label))
                        .font(.ui(size: 17, weight: .medium)).foregroundColor(Mono.text)
                        .focused($typing)
                        .submitLabel(.done)
                        .padding(.horizontal, 16).frame(minHeight: 52)
                        .liquidGlassPanel(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    FlowLayout(spacing: 8) {
                        ForEach(Self.suggestions, id: \.0) { name, symbol in
                            chip(name, symbol: symbol, on: title == name) { title = name; icon = symbol; typing = false }
                        }
                    }
                }

                section("Icon") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.icons, id: \.self) { symbol in
                                Button { Haptics.selection(); icon = symbol } label: {
                                    Image(systemName: symbol).font(.ui(size: 16, weight: .medium))
                                        .foregroundColor(icon == symbol ? Mono.onWhite : Mono.text)
                                        .frame(width: 44, height: 44)
                                        .background { Circle().fill(icon == symbol ? Mono.text : Color.white.opacity(0.06)) }
                                        .overlay { Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(symbol)
                                .accessibilityAddTraits(icon == symbol ? .isSelected : [])
                            }
                        }
                    }
                }

                section("When") {
                    BentoSegmented(options: [(Schedule.once, "Once"), (.daily, "Every day"), (.weekdays, "Some days")],
                                   selection: $schedule)
                    if schedule == .weekdays {
                        HStack(spacing: 6) {
                            ForEach(weekdayOrder, id: \.self) { wd in
                                let on = weekdays.contains(wd)
                                Button {
                                    Haptics.selection()
                                    if on { weekdays.remove(wd) } else { weekdays.insert(wd) }
                                } label: {
                                    Text(Calendar.current.veryShortWeekdaySymbols[wd - 1])
                                        .font(.ui(size: 14, weight: .semibold))
                                        .foregroundColor(on ? Mono.onWhite : Mono.text)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background { Capsule().fill(on ? Mono.text : Color.white.opacity(0.06)) }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Calendar.current.weekdaySymbols[wd - 1])
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                    dateRow(schedule == .once ? "On" : "Starts", $date)
                    if schedule != .once {
                        Toggle(isOn: $hasEnd.animation(.smooth)) {
                            Text("Ends").font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
                        }
                        .tint(.ncMoss)
                        if hasEnd { dateRow("Until", $end) }
                    }
                }

                Button("Add goal") { save() }
                    .buttonStyle(.bentoPrimary)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20).padding(.bottom, 30)
            .animation(.smooth(duration: 0.25), value: schedule)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .glassSheetBackground()
        .presentationCornerRadius(Bento.radius)
        .environment(\.colorScheme, .dark)
    }

    private var weekdayOrder: [Int] { (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 } }

    private func section(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(.bentoLabel).foregroundColor(Mono.label)
            content()
        }
    }

    private func chip(_ text: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            Label(text, systemImage: symbol)
                .font(.ui(size: 13, weight: .semibold))
                .foregroundColor(on ? Mono.onWhite : Mono.text)
                .padding(.horizontal, 12).frame(minHeight: 36)
                .background { Capsule().fill(on ? Mono.text : Color.white.opacity(0.06)) }
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func dateRow(_ label: String, _ value: Binding<Date>) -> some View {
        DatePicker(selection: value, displayedComponents: .date) {
            Text(label).font(.ui(size: 15, weight: .semibold)).foregroundColor(Mono.text)
        }
        .tint(.vitalisLime)
    }

    private func save() {
        let goal: Goal = switch schedule {
        case .once: Goal(title: title.trimmingCharacters(in: .whitespaces), icon: icon, start: date, end: date)
        case .daily: Goal(title: title.trimmingCharacters(in: .whitespaces), icon: icon, start: date, end: hasEnd ? end : nil)
        case .weekdays: Goal(title: title.trimmingCharacters(in: .whitespaces), icon: icon, start: date,
                             end: hasEnd ? end : nil, weekdays: Array(weekdays))
        }
        onSave(goal)
        dismiss()
    }
}
