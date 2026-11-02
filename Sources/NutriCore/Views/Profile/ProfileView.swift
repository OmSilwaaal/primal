import SwiftUI
import SwiftData

/// The Profile tab, in bento glass tiles on the shared backdrop: who you are (avatar, name, handle), your body
/// (weight, height, age) and the daily energy it works out to, then the screens that live here (Raw, Sun,
/// Friends, Settings) and signing out. Edit opens the same fields in place. Today's intake and the macro targets
/// live on Home and Data, and the legal documents in Settings, so they aren't repeated here.
struct ProfileView: View {
    @State private var pushed: SecondaryScreen?

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
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
                            bodyTiles(profile)
                                .transition(.opacity)
                        }
                    } else {
                        setUp
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
            .navigationDestination(isPresented: $showSettings) { SettingsView().pushedScreen() }
            .navigationDestination(item: $pushed) { $0.destination }
        }
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
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(.bentoRound)
                .accessibilityLabel("Settings")
        }
    }

    // MARK: - Identity

    /// Avatar, name and handle (or diet), with the rune large and faint in the corner.
    private func identity(_ profile: UserProfile) -> some View {
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
        .padding(.vertical, 4)
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

    /// Weight, height and age side by side, then the daily energy they work out to.
    private func bodyTiles(_ profile: UserProfile) -> some View {
        let activity = Self.activities.first { $0.0 == profile.activityLevel }?.1 ?? profile.activityLevel
        return VStack(spacing: Bento.gap) {
            // Three equal tiles in a row; stacked when large text no longer fits.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Bento.gap) { stats(profile) }.fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Bento.gap) { stats(profile) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Daily energy").font(.bentoLabel).foregroundColor(Mono.label)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Int(profile.dailyCalorieGoal).formatted()).font(.display(48)).foregroundColor(Mono.text)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text("kcal").font(.ui(size: 15, weight: .medium)).foregroundColor(Mono.label)
                }
                Text("\(activity) activity · \(profile.isMale ? "Male" : "Female")")
                    .font(.mono(11)).tracking(0.88).textCase(.uppercase).foregroundColor(Mono.label)
            }
            .bentoTile(padding: 18, art: .sun)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func stats(_ profile: UserProfile) -> some View {
        stat("Weight", "\(Int(profile.weightKg))", unit: "kg")
        stat("Height", "\(Int(profile.heightCm))", unit: "cm")
        stat("Age", "\(profile.age)", unit: nil)
    }

    private func stat(_ label: String, _ value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.bentoLabel).foregroundColor(Mono.label).lineLimit(1).fixedSize()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.bentoNumber(24)).tracking(Font.bentoTracking(24)).foregroundColor(Mono.text)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let unit { Text(unit).font(.ui(size: 12)).foregroundColor(Mono.label) }
            }
        }
        .bentoTile(padding: 14)
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
            row("Settings", "Account, privacy, subscription, legal", icon: "gearshape") { showSettings = true }
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
