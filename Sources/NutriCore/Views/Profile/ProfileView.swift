import SwiftUI
import SwiftData

/// The Profile tab, in bento glass tiles on the shared backdrop: one box for who you are (avatar, name, handle,
/// weight, height, age, activity), Vitalis Pro, the daily energy it works out to, the Goals calendar (tap for the
/// Goals page), then at the bottom the screens that live here (Raw, Sun, Friends, Settings) and signing out. Edit opens the same fields in place. Today's intake and the macro targets
/// live on Home and Data, and the legal documents in Settings, so they aren't repeated here.
enum ProfileRoute: Hashable { case settings, goals }

struct ProfileView: View {
    @State private var pushed: SecondaryScreen?

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var social = SocialService.shared
    @StateObject private var subscription = SubscriptionManager.shared

    @State private var isEditing = false
    /// Settings or Goals, pushed from here (one destination: SwiftUI honours only one `isPresented` push per view).
    @State private var route: ProfileRoute?
    @State private var showPaywall = false
    @State private var showManageSubscription = false
    @State private var goalsMonth = MonthMath.start(of: .now)
    @State private var draft = Draft()

    struct Draft {
        var sex = "Male", age = "", weight = "", height = "", activity = "moderate"
        var tdee: Double? {
            guard let a = Int(age), let w = Double(weight), let h = Double(height) else { return nil }
            return UserProfile.tdee(male: sex == "Male", weightKg: w, heightCm: h, age: a, activity: activity)
        }
    }

    private static let activities: [(String, String)] = [
        ("sedentary", "Sedentary"), ("light", "Light"), ("moderate", "Moderate"), ("active", "Active"), ("veryActive", "Very active"),
    ]

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            // No backdrop here: ContentView draws one that stays still while tabs change.
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Bento.gap) {
                    header.padding(.top, 8)

                    if let profile {
                        identity(profile)
                        if isEditing {
                            editor(profile)
                                .transition(.opacity.combined(with: .offset(y: 12)))
                        } else {
                            proTile
                            bodyTiles(profile)
                                .transition(.opacity)
                            GoalsCalendarTile(goal: profile.dailyCalorieGoal, month: $goalsMonth) {
                                Haptics.tap()
                                route = .goals
                            }
                        }
                    } else {
                        setUp
                        proTile
                    }

                    if !isEditing {
                        more
                        accountButton
                    }
                }
                .padding(.horizontal, Bento.margin)
                .padding(.bottom, 120)
                .animation(.spring(response: 0.42, dampingFraction: 0.88), value: isEditing)
            }
            .scrollDismissesKeyboard(.interactively)
            .glassLightFollowsScroll()
            .sharedBackdropRoot()
            .toolbar(.hidden, for: .navigationBar)
            .navigationTitle("Profile") // names the back button on pushed screens
            .navigationDestination(item: $pushed) { $0.destination }
            .navigationDestination(item: $route) { route in
                switch route {
                case .settings: SettingsView().pushedScreen()
                case .goals: GoalsDestination(month: goalsMonth).pushedScreen()
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(onNotNow: { showPaywall = false }, showsAccountButton: false)
            }
            .manageSubscriptionsSheet(isPresented: $showManageSubscription)
            .onChange(of: showManageSubscription) { _, shown in
                if !shown { Task { await subscription.refreshEntitlement() } }
            }
        }
    }

    // MARK: - Pro

    /// Vitalis Pro: what you have and a way to manage it, or what it adds and the plans.
    private var proTile: some View {
        let pro = subscription.isSubscribed
        return Button {
            Haptics.tap()
            if pro { showManageSubscription = true } else { showPaywall = true }
        } label: {
            HStack(spacing: 14) {
                AlgizMark().fill(pro ? Mono.onWhite : Mono.text)
                    .frame(width: 14, height: 18)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(pro ? Mono.text : Color.white.opacity(0.08)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(pro ? 0 : 0.16), lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pro ? "Vitalis Pro" : "Get Vitalis Pro").font(.ui(size: 16, weight: .semibold))
                        .foregroundColor(Mono.text)
                    Text(pro ? "Active · manage or change plan" : "Scanner, full nutrients, Health sync, app icons")
                        .font(.ui(size: 12)).foregroundColor(Mono.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if pro {
                    Image(systemName: "chevron.right").font(.ui(size: 12, weight: .semibold)).foregroundColor(Mono.label)
                } else {
                    Text("See plans").font(.ui(size: 13, weight: .semibold)).foregroundColor(Mono.onWhite)
                        .padding(.horizontal, 14).frame(minHeight: 34)
                        .background(Capsule().fill(Mono.text))
                        .fixedSize()
                }
            }
            .bentoTile(padding: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Profile").font(.bentoTitle).foregroundColor(Mono.text)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let profile, !isEditing {
                Button { startEditing(profile) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.bentoRound)
                    .accessibilityLabel("Edit profile")
            }
            Button { route = .settings } label: { Image(systemName: "gearshape") }
                .buttonStyle(.bentoRound)
                .accessibilityLabel("Settings")
        }
    }

    // MARK: - Identity

    /// One box for who you are: avatar, name and handle (or diet), then weight, height and age and your activity,
    /// with the rune large and faint in the corner.
    private func identity(_ profile: UserProfile) -> some View {
        let activity = Self.activities.first { $0.0 == profile.activityLevel }?.1 ?? profile.activityLevel
        return VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 14) {
            AvatarView(url: social.myProfile?.avatarUrl, name: displayName(profile), size: 60)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(profile)).font(.display(26)).foregroundColor(Mono.text)
                    .lineLimit(2).minimumScaleFactor(0.6)
                Text(social.myProfile.map { "@\($0.username)" } ?? profile.dietType)
                    .font(.mono(11)).tracking(0.88).textCase(.uppercase).foregroundColor(Mono.label).lineLimit(1)
            }
            Spacer(minLength: 0)
        }

        if !isEditing {
            // Side by side when they fit; stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) { stats(profile, divided: true) }
                VStack(alignment: .leading, spacing: 10) { stats(profile, divided: false) }
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1) }
            .transition(.opacity)

            Text("\(activity) activity · \(profile.isMale ? "Male" : "Female")")
                .font(.mono(11)).tracking(0.88).textCase(.uppercase).foregroundColor(Mono.label)
        }
        }
        .background(alignment: .bottomTrailing) {
            AlgizMark().fill(Mono.text.opacity(0.07))
                .frame(width: 96, height: 124)
                .offset(x: 26, y: 46)
                .accessibilityHidden(true)
        }
        .bentoTile(padding: 18)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Body

    /// The daily energy your body and activity work out to.
    private func bodyTiles(_ profile: UserProfile) -> some View {
        VStack(spacing: Bento.gap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Daily energy").font(.bentoLabel).foregroundColor(Mono.label)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Int(profile.dailyCalorieGoal).formatted()).font(.display(48)).foregroundColor(Mono.text)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text("kcal").font(.ui(size: 15, weight: .medium)).foregroundColor(Mono.label)
                }
                Text("From your weight, height, age and activity")
                    .font(.ui(size: 12)).foregroundColor(Mono.label)
            }
            .bentoTile(padding: 18, art: .sun)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func stats(_ profile: UserProfile, divided: Bool) -> some View {
        stat("Weight", "\(Int(profile.weightKg))", unit: "kg")
        if divided { divider }
        stat("Height", "\(Int(profile.heightCm))", unit: "cm")
        if divided { divider }
        stat("Age", "\(profile.age)", unit: nil)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1, height: 36).padding(.horizontal, 14)
    }

    private func stat(_ label: String, _ value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.bentoLabel).foregroundColor(Mono.label).lineLimit(1).fixedSize()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.bentoNumber(24)).tracking(Font.bentoTracking(24)).foregroundColor(Mono.text)
                    .lineLimit(1).fixedSize()
                    .contentTransition(.numericText())
                if let unit { Text(unit).font(.ui(size: 12)).foregroundColor(Mono.label).fixedSize() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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

    /// The screens that moved out of the tab bar, as rows in one glass tile.
    private var more: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("More").font(.bentoLabel).foregroundColor(Mono.label).padding(.bottom, 4)
            row("Raw", "Diet position, food safety, organ rotation", icon: "leaf", first: true) { pushed = .raw }
            row("Sun", "Time outside and today's vitamin D window", icon: "sun.max") { pushed = .sun }
            row("Friends", "Eat together, shared meals", icon: "person.2") { pushed = .friends }
            row("Settings", "Account, privacy, subscription, legal", icon: "gearshape") { route = .settings }
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

    /// Signs out, or for a guest, returns to the login screen.
    private var accountButton: some View {
        Button(authManager.isGuest ? "Log in or sign up" : "Sign out") { Task { await authManager.signOut() } }
            .buttonStyle(.bentoSecondary)
            .padding(.top, 4)
    }

    // MARK: - Editor

    private func editor(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            BentoSegmented(options: [("Male", "Male"), ("Female", "Female")], selection: $draft.sex)

            VStack(spacing: 0) {
                field("Age", $draft.age, .numberPad, first: true)
                field("Weight", $draft.weight, .decimalPad, unit: "kg")
                field("Height", $draft.height, .decimalPad, unit: "cm")
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Activity").font(.bentoLabel).foregroundColor(Mono.label)
                FlowLayout(spacing: 8) {
                    ForEach(Self.activities, id: \.0) { key, label in
                        activityChip(key, label)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("New daily energy").font(.bentoLabel).foregroundColor(Mono.label)
                Spacer()
                Text(draft.tdee.map { Int($0).formatted() } ?? "—").font(.bentoNumber(22)).foregroundColor(Mono.text)
                    .contentTransition(.numericText())
                    .animation(.smooth, value: draft.tdee.map(Int.init))
                Text("kcal").font(.ui(size: 12)).foregroundColor(Mono.label)
            }

            HStack(spacing: 10) {
                Button("Cancel") { isEditing = false }.buttonStyle(.bentoSecondary)
                Button("Save") { saveProfile(profile) }.buttonStyle(.bentoPrimary)
            }
        }
        .bentoTile(padding: 18)
    }

    private func activityChip(_ key: String, _ label: String) -> some View {
        let on = draft.activity == key
        return Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { draft.activity = key }
        } label: {
            Text(label).font(.ui(size: 14, weight: .semibold))
                .foregroundColor(on ? Mono.onWhite : Mono.text)
                .padding(.horizontal, 16).frame(minHeight: 40)
                .background {
                    Capsule().fill(on ? Mono.text : Color.white.opacity(0.08))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0 : 0.16), lineWidth: 1))
                }
                .padding(.vertical, 2)
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func field(_ label: String, _ text: Binding<String>, _ keyboard: UIKeyboardType,
                       unit: String? = nil, first: Bool = false) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.bentoBody).foregroundColor(Mono.text)
            Spacer()
            TextField("", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(.bentoNumber(18)).foregroundColor(Mono.text)
                .frame(width: 100)
                .accessibilityLabel(label)
            if let unit { Text(unit).font(.ui(size: 13)).foregroundColor(Mono.label).frame(width: 22, alignment: .leading) }
        }
        .frame(minHeight: 52)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }
        }
    }

    // MARK: - Actions

    private func displayName(_ profile: UserProfile) -> String {
        if let name = social.myProfile?.name, !name.isEmpty { return name }
        return profile.name.isEmpty ? "Your profile" : profile.name
    }

    private func startEditing(_ profile: UserProfile) {
        Haptics.tap()
        draft = Draft(sex: profile.isMale ? "Male" : "Female",
                      age: "\(profile.age)",
                      weight: "\(Int(profile.weightKg))",
                      height: "\(Int(profile.heightCm))",
                      activity: profile.activityLevel)
        isEditing = true
    }

    private func saveProfile(_ profile: UserProfile) {
        if let w = Double(draft.weight) { profile.weightKg = w }
        if let h = Double(draft.height) { profile.heightCm = h }
        if let a = Int(draft.age) { profile.age = a }
        profile.sex = draft.sex
        profile.activityLevel = draft.activity
        try? modelContext.save()
        isEditing = false
        ToastCenter.shared.show("Profile saved")
    }
}

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

// MARK: - Profile tile

/// The Goals bento on Profile: today large on the left (weekday over the date, then the daily goal), the month on
/// the right with a dot per day. Switch months with the arrows or a swipe; tap anywhere else for the Goals page.
struct GoalsCalendarTile: View {
    let goal: Double
    @Binding var month: Date
    var onOpen: () -> Void
    @State private var forward = true

    var body: some View {
        let now = Date.now
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(now.formatted(.dateTime.weekday(.wide)))
                    .font(.ui(size: 15, weight: .semibold)).foregroundColor(.ncMoss)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(now.formatted(.dateTime.day()))
                    .font(.display(64)).foregroundColor(Mono.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 10)
                HStack(spacing: 8) {
                    Capsule().fill(Color.ncMoss).frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Goals").font(.ui(size: 13, weight: .semibold)).foregroundColor(Mono.text)
                        Text("\(Int(goal).formatted()) kcal a day").font(.ui(size: 11)).foregroundColor(Mono.label)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(width: 104, alignment: .leading)
            .accessibilityElement(children: .combine)

            VStack(spacing: 4) {
                MonthSwitcher(month: $month)
                MonthCalendar(month: month, goal: goal)
                    .id(month)
                    .transition(.push(from: forward ? .trailing : .leading))
                    .monthSwipe($month)
            }
            .clipped()
        }
        .bentoTile(padding: 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onChange(of: month) { old, new in forward = new > old }
        .accessibilityAction(named: "Open goals", onOpen)
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
