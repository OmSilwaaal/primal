import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var meals: [MealEntry]
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var social = SocialService.shared

    @State private var isEditing = false
    @State private var showSettings = false
    @State private var weightStr = ""
    @State private var heightStr = ""
    @State private var ageStr = ""
    @State private var selectedSex = "Male"
    @State private var selectedActivity = "moderate"

    private var profile: UserProfile? { profiles.first }
    private var todaysMeals: [MealEntry] {
        Calendar.current.isDateInToday(Date()) ? meals.filter { Calendar.current.isDateInToday($0.date) } : []
    }
    private var weekTotal: Double { meals.filter { Date().timeIntervalSince($0.date) < 7*86400 }.totalCalories }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Space.section) {
                        PageHeader(title: "Profile", caption: social.myProfile.map { "@\($0.username)" } ?? "Account") {
                            HeaderIconButton(systemName: "gearshape", label: "Settings") { showSettings = true }
                        }

                        if let profile = profile {
                            RawCard(title: "Identity", index: "01") {
                                HStack(alignment: .center, spacing: 16) {
                                    AvatarView(url: social.myProfile?.avatarUrl, name: displayName(profile), size: 64)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(displayName(profile)).font(.serif(26)).foregroundColor(.ncPrimary).lineLimit(1).minimumScaleFactor(0.7)
                                        Text(profile.dietType).serifCaps(10).foregroundColor(.ncSecondary)
                                    }
                                    Spacer()
                                }
                            }

                            RawCard(title: "Body", index: "02") {
                                VStack(alignment: .leading, spacing: 22) {
                                    StatStrip(items: [
                                        .init(label: "Weight", value: "\(Int(profile.weightKg))", note: "kg"),
                                        .init(label: "Height", value: "\(Int(profile.heightCm))", note: "cm"),
                                        .init(label: "Age", value: "\(profile.age)", note: "years"),
                                        .init(label: "Sex", value: profile.sex.prefix(1).uppercased(), note: profile.sex.lowercased()),
                                    ])
                                    if isEditing {
                                        VStack(alignment: .leading, spacing: 20) {
                                            HStack(spacing: 16) {
                                                RawField(title: "Weight (kg)", text: $weightStr, keyboard: .decimalPad)
                                                RawField(title: "Height (cm)", text: $heightStr, keyboard: .decimalPad)
                                                RawField(title: "Age", text: $ageStr, keyboard: .numberPad)
                                            }
                                            HStack(spacing: 8) {
                                                ForEach(["Male", "Female"], id: \.self) { sex in
                                                    Chip(label: sex, selected: selectedSex == sex) { selectedSex = sex }
                                                }
                                            }
                                            HStack(spacing: 10) {
                                                Button("Save") { saveProfile(profile); isEditing = false }.buttonStyle(.primal)
                                                Button("Cancel") { isEditing = false }.buttonStyle(SecondaryButtonStyle(height: 54))
                                            }
                                        }
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    } else {
                                        Button("Edit body stats") { startEditing(profile) }.buttonStyle(.primalSecondary)
                                    }
                                }
                            }

                            RawCard(title: "Intake", index: "03") {
                                StatStrip(items: [
                                    .init(label: "Today", value: Int(todaysMeals.totalCalories).formatted(), note: "kcal"),
                                    .init(label: "7 days", value: Int(weekTotal).formatted(), note: "kcal"),
                                    .init(label: "Meals", value: "\(todaysMeals.count)", note: "today"),
                                ])
                            }

                            RawCard(title: "Account", index: "04") {
                                VStack(spacing: 0) {
                                    Button { showSettings = true } label: {
                                        NavRow(icon: "gearshape", title: "Settings", detail: "Account, privacy, subscription")
                                    }.buttonStyle(.plain)
                                    Button { Task { await authManager.signOut() } } label: {
                                        VStack(spacing: 0) {
                                            HStack {
                                                Text("Sign out").font(.system(size: 17, weight: .medium)).foregroundColor(.ncError)
                                                Spacer()
                                            }
                                            .padding(.vertical, 18)
                                            Hairline(opacity: 0.12)
                                        }
                                        .contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Set up your profile so goals can be calculated for you.").font(.serif(18)).foregroundColor(.ncPrimary)
                                NavigationLink(destination: ProfileSetupView()) { Text("Set up profile") }.buttonStyle(.primal)
                            }
                        }
                    }
                    .padding(.horizontal, Space.margin)
                    .padding(.top, 12)
                    .padding(.bottom, 140)
                    .animation(.smooth, value: isEditing)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
        }
    }

    private func displayName(_ profile: UserProfile) -> String {
        if let name = social.myProfile?.name, !name.isEmpty { return name }
        return profile.name.isEmpty ? "Your profile" : profile.name
    }

    private func startEditing(_ profile: UserProfile) {
        weightStr = "\(Int(profile.weightKg))"
        heightStr = "\(Int(profile.heightCm))"
        ageStr = "\(profile.age)"
        selectedSex = profile.isMale ? "Male" : "Female"
        selectedActivity = profile.activityLevel
        isEditing.toggle()
    }

    private func saveProfile(_ profile: UserProfile) {
        if let w = Double(weightStr) { profile.weightKg = w }
        if let h = Double(heightStr) { profile.heightCm = h }
        if let a = Int(ageStr) { profile.age = a }
        profile.sex = selectedSex
        profile.activityLevel = selectedActivity
        try? modelContext.save()
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
