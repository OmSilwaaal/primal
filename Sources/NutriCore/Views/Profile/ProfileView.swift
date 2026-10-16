import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var meals: [MealEntry]
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var social = SocialService.shared

    @State private var isEditing = false
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
                Color.ncSurfaceContLowest.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {

                        // ── Header ───────────────────────────────────────────
                        HStack(spacing: 10) {
                            PrimalLogoMark()
                            VStack(alignment: .leading, spacing: 1) {
                                Text("PRIMAL")
                                    .font(.system(size: 20, weight: .semibold))
                                    .tracking(2).foregroundColor(.ncPrimary)
                                Text("TELEMETRY // PROFILE")
                                    .font(.ncLabelMonoReg).tracking(2).foregroundColor(.ncSecondary)
                            }
                            Spacer()
                            NavigationLink(destination: SettingsView()) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.ncSecondary)
                                    .frame(width: 44, height: 44)
                                    .background(Color.ncSurfaceContHigh)
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.08), lineWidth: 1))
                            }
                            .smoothButton()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                        if let profile = profile {
                            // ── Identity Card ────────────────────────────────
                            VStack(spacing: 12) {
                                HStack {
                                    AvatarView(url: social.myProfile?.avatarUrl, name: displayName(profile), size: 56)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(displayName(profile))
                                            .font(.system(size: 18, weight: .semibold))
                                            .tracking(1).foregroundColor(.ncPrimary)
                                        Text(social.myProfile.map { "@\($0.username)" } ?? profile.dietType)
                                            .font(.ncLabelMonoReg).tracking(1.5).foregroundColor(.ncSecondary)
                                    }
                                    Spacer()
                                    Button { startEditing(profile) } label: {
                                        Text(isEditing ? "CANCEL" : "EDIT")
                                            .font(.ncLabelMonoBold).tracking(2)
                                            .foregroundColor(.ncPrimary)
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(Color.ncSurfaceContHighest)
                                            .cornerRadius(4)
                                    }
                                    .smoothButton()
                                }

                                // Biometric grid
                                HStack(spacing: 8) {
                                    ProfileStatTile(label: "WEIGHT", value: "\(Int(profile.weightKg))", unit: "KG")
                                    ProfileStatTile(label: "HEIGHT", value: "\(Int(profile.heightCm))", unit: "CM")
                                    ProfileStatTile(label: "AGE", value: "\(profile.age)", unit: "YRS")
                                    ProfileStatTile(label: "SEX", value: profile.sex.prefix(1).uppercased(), unit: profile.sex.uppercased())
                                }
                            }
                            .padding(16)
                            .background(Color.ncSurfaceCont)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.06), lineWidth: 1))
                            .padding(.horizontal, 16)

                            // ── Edit Form ────────────────────────────────────
                            if isEditing {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("BIOMETRIC OVERRIDE")
                                        .font(.ncLabelMonoBold).tracking(2).foregroundColor(.ncSecondary)

                                    HStack(spacing: 10) {
                                        StitchInputField(label: "WEIGHT KG", text: $weightStr)
                                        StitchInputField(label: "HEIGHT CM", text: $heightStr)
                                        StitchInputField(label: "AGE", text: $ageStr)
                                    }

                                    HStack(spacing: 8) {
                                        ForEach(["Male", "Female"], id: \.self) { sex in
                                            Button { selectedSex = sex } label: {
                                                Text(sex.uppercased())
                                                    .font(.ncLabelMonoBold).tracking(2)
                                                    .foregroundColor(selectedSex == sex ? .ncOnPrimary : .ncSecondary)
                                                    .frame(maxWidth: .infinity).frame(height: 36)
                                                    .background(selectedSex == sex ? Color.ncPrimary : Color.ncSurfaceContHigh)
                                                    .cornerRadius(4)
                                            }
                                            .smoothButton()
                                        }
                                    }

                                    Button {
                                        saveProfile(profile)
                                        isEditing = false
                                    } label: {
                                        Text("COMMIT BIOMETRIC DATA")
                                            .font(.ncLabelMonoBold).tracking(2)
                                            .foregroundColor(.ncOnPrimary)
                                            .frame(maxWidth: .infinity).frame(height: 48)
                                            .background(Color.ncPrimary)
                                            .cornerRadius(8)
                                    }
                                    .smoothButton()
                                }
                                .padding(16)
                                .background(Color.ncSurfaceCont)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.06), lineWidth: 1))
                                .padding(.horizontal, 16)
                            }

                            // ── Telemetry Stats ──────────────────────────────
                            VStack(alignment: .leading, spacing: 12) {
                                Text("OPERATIONAL TELEMETRY")
                                    .font(.ncLabelMonoBold).tracking(2).foregroundColor(.ncSecondary)
                                HStack(spacing: 8) {
                                    TelemetryTile(label: "TODAY", value: "\(Int(todaysMeals.totalCalories))", unit: "KCAL")
                                    TelemetryTile(label: "7-DAY", value: "\(Int(weekTotal))", unit: "KCAL")
                                    TelemetryTile(label: "MEALS", value: "\(todaysMeals.count)", unit: "TODAY")
                                }
                            }
                            .padding(16)
                            .background(Color.ncSurfaceCont)
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.06), lineWidth: 1))
                            .padding(.horizontal, 16)

                            // ── Sign Out ─────────────────────────────────────
                            Button {
                                Task { await authManager.signOut() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 13))
                                    Text("TERMINATE SESSION")
                                        .font(.ncLabelMonoBold).tracking(2)
                                }
                                .foregroundColor(.ncError)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Color.red.opacity(0.08))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.red.opacity(0.3), lineWidth: 1))
                            }
                            .smoothButton()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 100)

                        } else {
                            // No profile yet
                            NavigationLink(destination: ProfileSetupView()) {
                                Text("INITIALISE BIOMETRIC PROFILE")
                                    .font(.ncLabelMonoBold).tracking(2)
                                    .foregroundColor(.ncOnPrimary)
                                    .frame(maxWidth: .infinity).frame(height: 52)
                                    .background(Color.ncPrimary).cornerRadius(12)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
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
        VStack(spacing: 2) {
            Text(label).font(.ncLabelMonoReg).tracking(1.5).foregroundColor(.ncSecondary)
            Text(value).font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundColor(.ncPrimary)
            Text(unit).font(.system(size: 8, design: .monospaced)).tracking(1).foregroundColor(.ncSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.ncSurfaceContLow)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

struct TelemetryTile: View {
    let label, value, unit: String
    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.ncLabelMonoReg).tracking(1.5).foregroundColor(.ncSecondary)
            Text(value).font(.ncMetricMobile).foregroundColor(.ncPrimary)
            Text(unit).font(.system(size: 8, design: .monospaced)).tracking(1).foregroundColor(.ncSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.ncSurfaceContLow)
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
}

struct StitchInputField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.ncLabelMonoReg).tracking(1.5).foregroundColor(.ncSecondary)
            TextField("", text: $text)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.ncPrimary)
                .keyboardType(.decimalPad)
                .padding(10)
                .background(Color(hex: "#0A0A0A"))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }
}
