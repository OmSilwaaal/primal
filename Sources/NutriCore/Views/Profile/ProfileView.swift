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
                    VStack(spacing: 12) {
                        // ── Header ───────────────────────────────────────────
                        ZStack(alignment: .topTrailing) {
                            PageHeader(title: "Profile", caption: social.myProfile.map { "@\($0.username)" } ?? "Account")
                            Button { showSettings = true } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 15, weight: .medium)).foregroundColor(.ncPrimary)
                                    .frame(width: 36, height: 36)
                                    .overlay(Rectangle().stroke(Color.ncPrimary.opacity(0.5), lineWidth: 1))
                            }
                            .smoothButton()
                        }
                        .padding(.horizontal, 16).padding(.top, 12)

                        if let profile = profile {
                            // ── Identity ─────────────────────────────────────
                            VStack(spacing: 16) {
                                HStack(spacing: 14) {
                                    AvatarView(url: social.myProfile?.avatarUrl, name: displayName(profile), size: 56)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(displayName(profile)).font(.ncTitle).foregroundColor(.ncPrimary)
                                        Text(profile.dietType).spacedCaps(10, tracking: 2).foregroundColor(.ncSecondary)
                                    }
                                    Spacer()
                                    Button { startEditing(profile) } label: {
                                        Text(isEditing ? "Cancel" : "Edit")
                                            .spacedCaps(11, tracking: 1.6).fontWeight(.bold)
                                            .foregroundColor(.ncPrimary)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .overlay(Rectangle().stroke(Color.ncPrimary.opacity(0.4), lineWidth: 1))
                                    }
                                    .smoothButton()
                                }

                                HStack(spacing: 8) {
                                    ProfileStatTile(label: "Weight", value: "\(Int(profile.weightKg))", unit: "kg")
                                    ProfileStatTile(label: "Height", value: "\(Int(profile.heightCm))", unit: "cm")
                                    ProfileStatTile(label: "Age", value: "\(profile.age)", unit: "yrs")
                                    ProfileStatTile(label: "Sex", value: profile.sex.prefix(1).uppercased(), unit: profile.sex)
                                }
                            }
                            .padding(16)
                            .glassCard(radius: 3)
                            .padding(.horizontal, 16)

                            // ── Edit form ────────────────────────────────────
                            if isEditing {
                                VStack(alignment: .leading, spacing: 14) {
                                    RuleLabel(text: "Edit body stats")
                                    HStack(spacing: 10) {
                                        StitchInputField(label: "Weight kg", text: $weightStr)
                                        StitchInputField(label: "Height cm", text: $heightStr)
                                        StitchInputField(label: "Age", text: $ageStr)
                                    }
                                    HStack(spacing: 8) {
                                        ForEach(["Male", "Female"], id: \.self) { sex in
                                            Chip(label: sex, selected: selectedSex == sex) { selectedSex = sex }
                                        }
                                    }
                                    Button("Save changes") {
                                        saveProfile(profile)
                                        isEditing = false
                                    }
                                    .buttonStyle(.primal)
                                }
                                .padding(16)
                                .glassCard(radius: 3)
                                .padding(.horizontal, 16)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // ── Stats ────────────────────────────────────────
                            VStack(alignment: .leading, spacing: 14) {
                                RuleLabel(text: "Intake")
                                HStack(spacing: 8) {
                                    TelemetryTile(label: "Today", value: "\(Int(todaysMeals.totalCalories))", unit: "kcal")
                                    TelemetryTile(label: "7 days", value: "\(Int(weekTotal))", unit: "kcal")
                                    TelemetryTile(label: "Meals", value: "\(todaysMeals.count)", unit: "today")
                                }
                            }
                            .padding(16)
                            .glassCard(radius: 3)
                            .padding(.horizontal, 16)

                            // ── Sign out ─────────────────────────────────────
                            Button {
                                Task { await authManager.signOut() }
                            } label: {
                                Text("Sign out")
                                    .spacedCaps(12, tracking: 1.6).fontWeight(.bold)
                                    .foregroundColor(.ncError)
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .overlay(Rectangle().stroke(Color.ncError.opacity(0.5), lineWidth: 1))
                            }
                            .smoothButton()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 100)

                        } else {
                            NavigationLink(destination: ProfileSetupView()) {
                                Text("Set up profile")
                                    .font(.system(size: 13, weight: .heavy)).tracking(1.4).textCase(.uppercase)
                                    .foregroundColor(.ncOnPrimary)
                                    .frame(maxWidth: .infinity).frame(height: 52)
                                    .background(Color.ncPrimary)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
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
            Text(label).spacedCaps(9, tracking: 1.4).foregroundColor(.ncSecondary)
            Text(value).font(.brutal(20, weight: .heavy)).foregroundColor(.ncPrimary)
            Text(unit).spacedCaps(8, tracking: 1.2).foregroundColor(.ncSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.ncSurfaceContLow)
        .overlay(Rectangle().stroke(Color.ncPrimary.opacity(0.1), lineWidth: 1))
    }
}

struct TelemetryTile: View {
    let label, value, unit: String
    var body: some View {
        VStack(spacing: 3) {
            Text(label).spacedCaps(9, tracking: 1.4).foregroundColor(.ncSecondary)
            Text(value).font(.brutal(24, weight: .heavy)).foregroundColor(.ncPrimary).minimumScaleFactor(0.6).lineLimit(1)
            Text(unit).spacedCaps(8, tracking: 1.2).foregroundColor(.ncSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.ncSurfaceContLow)
        .overlay(Rectangle().stroke(Color.ncPrimary.opacity(0.1), lineWidth: 1))
    }
}

struct StitchInputField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).spacedCaps(9, tracking: 1.4).foregroundColor(.ncSecondary)
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
