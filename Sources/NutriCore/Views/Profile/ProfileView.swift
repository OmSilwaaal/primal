import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    
    @State private var weightStr: String = ""
    @State private var heightStr: String = ""
    @State private var ageStr: String = ""
    @State private var selectedActivity: String = "moderate"
    @State private var selectedSex: String = "male"
    
    @State private var isEditing = false
    
    private var profile: UserProfile? {
        profiles.first
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.ncBg.ignoresSafeArea()
                
                if let profile = profile {
                    ScrollView {
                        VStack(spacing: 32) {
                            
                            // Minimal Header
                            ZStack(alignment: .topTrailing) {
                                VStack(spacing: 8) {
                                    Text("PROFILE")
                                        .font(.system(size: 12, weight: .bold))
                                        .tracking(2)
                                        .foregroundColor(.ncSecondary)
                                    
                                    Text(profile.name.uppercased())
                                        .font(.system(size: 24, weight: .regular))
                                        .foregroundColor(.ncPrimary)
                                }
                                .frame(maxWidth: .infinity)
                                
                                NavigationLink(destination: SettingsView()) {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 20, weight: .regular))
                                        .foregroundColor(.ncPrimary)
                                        .padding(.trailing, 8)
                                }
                                .smoothButton()
                            }
                            .padding(.top, 30)
                            
                            // Stats Summary
                            if !isEditing {
                                HStack(spacing: 16) {
                                    StatBox(icon: "scalemass", title: "WEIGHT", value: "\(Int(profile.weightKg)) KG")
                                    StatBox(icon: "ruler", title: "HEIGHT", value: "\(Int(profile.heightCm)) CM")
                                    StatBox(icon: "calendar", title: "AGE", value: "\(profile.age)")
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("DAILY TDEE")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(1.5)
                                        .foregroundColor(.ncSecondary)
                                    
                                    HStack(alignment: .firstTextBaseline) {
                                        Text("\(Int(profile.dailyCalorieGoal))")
                                            .font(.system(size: 32, weight: .regular))
                                            .foregroundColor(.ncPrimary)
                                        Text("KCAL")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(.ncSecondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color.ncSurface)
                                .cornerRadius(8)
                            }
                            
                            // Editor Form
                            if isEditing {
                                editForm(for: profile)
                            }
                            
                            // Actions
                            Button(action: {
                                if isEditing {
                                    saveProfile(profile)
                                } else {
                                    startEditing(profile)
                                }
                            }) {
                                Text(isEditing ? "SAVE" : "EDIT")
                                    .font(.system(size: 14, weight: .bold))
                                    .tracking(1)
                                    .foregroundColor(.ncBg)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.ncPrimary)
                                    .cornerRadius(8)
                            }
                            .smoothButton()
                            
                            if !isEditing {
                                Button("SIGN OUT") {
                                    Task {
                                        await AuthManager.shared.signOut()
                                    }
                                }
                                .font(.system(size: 12, weight: .bold))
                                .tracking(1)
                                .foregroundColor(.ncSecondary)
                                .padding(.top, 20)
                                .smoothButton()
                            }
                        }
                        .padding()
                    }
                } else {
                    Text("NO PROFILE")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.ncSecondary)
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    @ViewBuilder
    private func editForm(for profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            Picker("Sex", selection: $selectedSex) {
                Text("Male").tag("male")
                Text("Female").tag("female")
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 8)
            
            MinimalTextField(title: "AGE", text: $ageStr, pad: .numberPad)
            MinimalTextField(title: "WEIGHT (KG)", text: $weightStr, pad: .decimalPad)
            MinimalTextField(title: "HEIGHT (CM)", text: $heightStr, pad: .decimalPad)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("ACTIVITY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.ncSecondary)
                
                Menu {
                    Button("Sedentary") { selectedActivity = "sedentary" }
                    Button("Light") { selectedActivity = "light" }
                    Button("Moderate") { selectedActivity = "moderate" }
                    Button("Active") { selectedActivity = "active" }
                    Button("Very Active") { selectedActivity = "veryActive" }
                } label: {
                    HStack {
                        Text(selectedActivity.activityDisplayName.uppercased())
                            .font(.system(size: 14))
                            .foregroundColor(.ncPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .foregroundColor(.ncSecondary)
                    }
                    .padding()
                    .background(Color.ncSurface2)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.ncSurface)
        .cornerRadius(8)
    }
    
    private func startEditing(_ profile: UserProfile) {
        weightStr = String(format: "%.0f", profile.weightKg)
        heightStr = String(format: "%.0f", profile.heightCm)
        ageStr = "\(profile.age)"
        selectedSex = profile.sex
        selectedActivity = profile.activityLevel
        withAnimation { isEditing = true }
    }
    
    private func saveProfile(_ profile: UserProfile) {
        if let w = Double(weightStr) { profile.weightKg = w }
        if let h = Double(heightStr) { profile.heightCm = h }
        if let a = Int(ageStr) { profile.age = a }
        profile.sex = selectedSex
        profile.activityLevel = selectedActivity
        withAnimation { isEditing = false }
    }
}

struct MinimalTextField: View {
    let title: String
    @Binding var text: String
    let pad: UIKeyboardType
    
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.ncSecondary)
                .frame(width: 80, alignment: .leading)
            TextField("", text: $text)
                .keyboardType(pad)
                .font(.system(size: 14))
                .foregroundColor(.ncPrimary)
                .padding()
                .background(Color.ncSurface2)
                .cornerRadius(8)
        }
    }
}

struct StatBox: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.ncPrimary)
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(.ncSecondary)
            Text(value)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.ncPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.ncSurface)
        .cornerRadius(8)
    }
}
