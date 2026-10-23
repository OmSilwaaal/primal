import SwiftUI
import SwiftData

struct ProfileView: View {
    var onOpen: (SecondaryScreen) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var meals: [MealEntry]
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var social = SocialService.shared

    @State private var isEditing = false
    @State private var showSettings = false
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

    init(onOpen: @escaping (SecondaryScreen) -> Void = { _ in }) {
        self.onOpen = onOpen
        let start = Calendar.current.startOfDay(for: .now)
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start })
    }

    private var profile: UserProfile? { profiles.first }
    private var todaysMeals: [MealEntry] { meals.filter { Calendar.current.isDateInToday($0.date) } }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let profile {
                            hero(profile)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                            if isEditing {
                                editor(profile)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            } else {
                                summary(profile)
                                    .transition(.opacity)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Profile").monoLabel()
                                Text("Set up your profile so goals can be calculated for you.")
                                    .font(.system(size: 15)).foregroundColor(.ncPrimary)
                                NavigationLink(destination: ProfileSetupView()) { Text("Set up profile") }.buttonStyle(.vitalis)
                                more
                                accountButton
                            }
                            .padding(.horizontal, Space.margin)
                            .padding(.top, 12)
                        }
                    }
                    .padding(.bottom, 120)
                    .animation(.smooth, value: isEditing)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
        }
    }

    // MARK: - Hero

    private func hero(_ profile: UserProfile) -> some View {
        let goal = profile.dailyCalorieGoal
        let pct = goal > 0 ? Int((min(todaysMeals.totalCalories / goal, 1) * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 12) {
                AvatarView(url: social.myProfile?.avatarUrl, name: displayName(profile), size: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                VStack(alignment: .leading, spacing: 3) {
                    Text("VITALIS").font(.display(18)).tracking(0.36).foregroundColor(.ncPrimary)
                    Text(social.myProfile.map { "@\($0.username)" } ?? profile.dietType)
                        .font(.mono(11)).tracking(1.54).textCase(.uppercase).foregroundColor(.ncSecondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if !isEditing {
                    Button { startEditing(profile) } label: {
                        Text("EDIT").font(.mono(11, .semibold)).tracking(1.1).foregroundColor(.ncPrimary)
                            .padding(.horizontal, 16).frame(height: 40)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(PressScaleStyle(scale: 0.96))
                    .frame(minHeight: 44)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Profile").monoLabel()
                Text(displayName(profile)).font(.display(44)).tracking(-1.76).foregroundColor(.ncPrimary)
                    .lineLimit(2).minimumScaleFactor(0.6)
                Text("\(todaysMeals.count) FOODS LOGGED TODAY · \(pct)% OF TARGET")
                    .font(.mono(12)).tracking(0.72).foregroundColor(.ncSoft)
            }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 22)
        .background(alignment: .bottomTrailing) {
            Text("VITALIS").font(.display(120)).tracking(-7.2).foregroundColor(.ncPrimary.opacity(0.05))
                .fixedSize().offset(x: 28, y: 34)
                .accessibilityHidden(true)
        }
        .background {
            LinearGradient(stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .white.opacity(0.03), location: 0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .glass(.clear, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 20, y: 20)
    }

    // MARK: - Summary

    private func summary(_ profile: UserProfile) -> some View {
        let goals = NutrientGoals.from(profile)
        let activity = Self.activities.first { $0.0 == profile.activityLevel }?.1 ?? profile.activityLevel
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                stat("Weight", "\(Int(profile.weightKg))", unit: "KG")
                stat("Height", "\(Int(profile.heightCm))", unit: "CM")
                stat("Age", "\(profile.age)")
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 6) {
                Text("Daily TDEE").monoLabel()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Int(profile.dailyCalorieGoal).formatted()).font(.display(72)).tracking(-2.88).foregroundColor(.ncPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("KCAL").font(.mono(13)).foregroundColor(.ncSecondary)
                }
                Text("\(activity) activity · \(profile.isMale ? "Male" : "Female")".uppercased())
                    .font(.mono(11)).tracking(1.1).foregroundColor(.ncSecondary)
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, 28)

            VStack(spacing: 0) {
                Rule()
                target("Protein", "\(Int(goals.protein)) g")
                target("Carbohydrates", "\(Int(goals.carbohydrates)) g")
                target("Fat", "\(Int(goals.fat)) g")
                target("Fiber", "\(Int(goals.fiber)) g")
                target("Sodium (max)", "\(Int(goals.sodium).formatted()) mg")
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 12) {
                Button("Edit profile") { startEditing(profile) }.buttonStyle(.vitalis)
                more.padding(.top, 16)
                accountButton
            }
            .padding(.horizontal, Space.margin)
            .padding(.top, 24)
        }
    }

    /// Signs out, or for a guest, returns to the login screen.
    private var accountButton: some View {
        Button(authManager.isGuest ? "Log in or sign up" : "Sign out") { Task { await authManager.signOut() } }
            .buttonStyle(TextButtonStyle(height: 48))
            .frame(maxWidth: .infinity)
    }

    /// Screens that moved out of the tab bar.
    private var more: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("More").monoLabel()
            VStack(spacing: 0) {
                Rule()
                row("Raw", "Diet position, food safety, organ rotation") { onOpen(.raw) }
                row("Sun", "Time outside and today's vitamin D window") { onOpen(.sun) }
                row("Friends", "Eat together, shared meals") { onOpen(.friends) }
                row("Settings", "Account, privacy, subscription") { showSettings = true }
            }
        }
    }

    private func row(_ title: String, _ detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { NavRow(icon: "", title: title, detail: detail) }
            .buttonStyle(.plain)
    }

    private func stat(_ label: String, _ value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).monoLabel()
            (Text(value).font(.system(size: 22)) + Text(unit.map { " \($0)" } ?? "").font(.mono(12)).foregroundColor(.ncSecondary))
                .foregroundColor(.ncPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.margin).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private func target(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundColor(.ncPrimary)
            Spacer()
            Text(value).font(.mono(13)).foregroundColor(.ncPrimary)
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Hairline(opacity: 0.28) }
    }

    // MARK: - Editor

    private func editor(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassSegmented(options: [("Male", "Male"), ("Female", "Female")], selection: $draft.sex)

            VStack(spacing: 0) {
                Rule()
                field("Age", $draft.age, .numberPad)
                field("Weight (kg)", $draft.weight, .decimalPad)
                field("Height (cm)", $draft.height, .decimalPad)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Activity").monoLabel()
                FlowLayout(spacing: 8) {
                    ForEach(Self.activities, id: \.0) { key, label in
                        OptionChip(label: label, selected: draft.activity == key) { draft.activity = key }
                    }
                }
            }

            (Text("NEW TDEE → ") + Text(draft.tdee.map { "\(Int($0).formatted()) KCAL" } ?? "—").foregroundColor(.ncPrimary))
                .font(.mono(12)).foregroundColor(.ncSecondary)

            Button("Save") { saveProfile(profile) }.buttonStyle(.vitalis)
            Button("Cancel") { isEditing = false }
                .buttonStyle(TextButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, 24)
    }

    private func field(_ label: String, _ text: Binding<String>, _ keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label.uppercased()).font(.mono(11)).tracking(1.32).foregroundColor(.ncSecondary)
            Spacer()
            TextField("", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 18)).foregroundColor(.ncPrimary)
                .frame(width: 120)
        }
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { Hairline(opacity: 0.28) }
    }

    // MARK: - Actions

    private func displayName(_ profile: UserProfile) -> String {
        if let name = social.myProfile?.name, !name.isEmpty { return name }
        return profile.name.isEmpty ? "Your profile" : profile.name
    }

    private func startEditing(_ profile: UserProfile) {
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

// MARK: - Supporting Views
struct ProfileStatTile: View {
    let label, value, unit: String
    var body: some View {
        VStack(spacing: 3) {
            Text(label).spacedCaps(11, tracking: 1.4).foregroundColor(.ncSecondary)
            Text(value).font(.brutal(20, weight: .heavy)).foregroundColor(.ncPrimary)
            Text(unit).spacedCaps(11, tracking: 1.2).foregroundColor(.ncSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

struct TelemetryTile: View {
    let label, value, unit: String
    var body: some View {
        VStack(spacing: 3) {
            Text(label).spacedCaps(11, tracking: 1.4).foregroundColor(.ncSecondary)
            Text(value).font(.brutal(24, weight: .heavy)).foregroundColor(.ncPrimary).minimumScaleFactor(0.6).lineLimit(1)
            Text(unit).spacedCaps(11, tracking: 1.2).foregroundColor(.ncSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

struct StitchInputField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).spacedCaps(11, tracking: 1.4).foregroundColor(.ncSecondary)
            TextField("", text: $text)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.ncPrimary)
                .keyboardType(.decimalPad)
                .padding(10)
                .background(Color.ncSurfaceContHigh)
                .overlay(Rectangle().stroke(Color.ncPrimary.opacity(0.18), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }
}
