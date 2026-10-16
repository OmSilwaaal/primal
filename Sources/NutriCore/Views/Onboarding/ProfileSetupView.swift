import SwiftUI
import SwiftData

struct ProfileSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    @State private var currentStep = 1
    let totalSteps = 6
    
    // State Variables
    @State private var ageGroup = "18-35"
    @State private var sex = "Male"
    @State private var pregnancyStatus = "None"
    @State private var lifestyle = "Moderate"
    @State private var weightLbs: String = ""
    @State private var heightFt: String = ""
    @State private var heightIn: String = ""
    @State private var location: String = ""
    @State private var selectedDiet = "Carnivore"
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // Progress Bar
                ProgressView(value: Double(currentStep), total: Double(totalSteps))
                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                
                Spacer()
                
                // Content with sliding transition
                Group {
                    switch currentStep {
                    case 1:
                        AgeGroupStep(selected: $ageGroup, onNext: nextStep)
                    case 2:
                        BiologicalStep(sex: $sex, pregnancyStatus: $pregnancyStatus, onNext: nextStep)
                    case 3:
                        LifestyleStep(selected: $lifestyle, onNext: nextStep)
                    case 4:
                        StatsStep(weightLbs: $weightLbs, heightFt: $heightFt, heightIn: $heightIn, onNext: nextStep)
                    case 5:
                        LocationStep(location: $location, onNext: nextStep)
                    case 6:
                        DietStep(selected: $selectedDiet, onFinish: finishSetup)
                    default:
                        EmptyView()
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                .id(currentStep)
                
                Spacer()
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
    }
    
    private func nextStep() {
        withAnimation {
            if currentStep < totalSteps {
                currentStep += 1
            }
        }
    }
    
    private func finishSetup() {
        let profile = UserProfile()
        profile.ageGroup = ageGroup
        switch ageGroup {
        case "Under 18": profile.age = 16
        case "36-50":    profile.age = 43
        case "Over 50":  profile.age = 58
        default:         profile.age = 26
        }
        profile.sex = sex
        profile.pregnancyStatus = pregnancyStatus
        
        switch lifestyle {
        case "Not Active": profile.activityLevel = "sedentary"
        case "Medium": profile.activityLevel = "moderate"
        case "Active": profile.activityLevel = "active"
        default: profile.activityLevel = "moderate"
        }
        
        let w = Double(weightLbs) ?? 150.0
        profile.weightKg = w / 2.20462
        profile.goalWeightKg = profile.weightKg // Simplified for now
        
        let ft = Double(heightFt) ?? 5.0
        let inc = Double(heightIn) ?? 8.0
        let totalInches = (ft * 12) + inc
        profile.heightCm = totalInches * 2.54
        
        profile.location = location
        profile.dietType = selectedDiet
        
        modelContext.insert(profile)
        try? modelContext.save()
        
        // Immediately dismiss the onboarding so the user isn't stuck
        withAnimation {
            hasCompletedOnboarding = true
        }
        
        Task {
            // Push to Supabase
            if let user = try? await supabase.auth.session.user {
                let fullName = user.userMetadata["full_name"]?.stringValue ?? user.userMetadata["name"]?.stringValue
                if let fullName, !fullName.isEmpty {
                    profile.name = fullName
                    try? modelContext.save()
                }
                let supabaseProfile = SupabaseProfile(
                    id: user.id.uuidString,
                    name: profile.name,
                    ageGroup: ageGroup,
                    sex: sex,
                    pregnancyStatus: pregnancyStatus,
                    location: location,
                    weightKg: profile.weightKg,
                    heightCm: profile.heightCm,
                    activityLevel: profile.activityLevel,
                    dietType: selectedDiet
                )
                
                do {
                    try await supabase.from("profiles").upsert(supabaseProfile).execute()
                    print("Successfully pushed profile to Supabase.")
                } catch {
                    print("Error pushing to Supabase: \(error)")
                }
            }
            
            // Request HealthKit permissions in the background after dismissal
            try? await HealthKitManager.shared.requestAuthorization()
        }
    }
}

// MARK: - Step 1: Age Group
struct AgeGroupStep: View {
    @Binding var selected: String
    let onNext: () -> Void
    let options = ["Under 18", "18-35", "36-50", "Over 50"]
    
    var body: some View {
        StepContainer(title: "AGE GROUP", subtitle: "Select your generation.") {
            OptionList(options: options, selected: $selected)
            NextButton(action: onNext, isDisabled: false)
        }
    }
}

// MARK: - Step 2: Biological Status
struct BiologicalStep: View {
    @Binding var sex: String
    @Binding var pregnancyStatus: String
    let onNext: () -> Void
    
    var body: some View {
        StepContainer(title: "BIOLOGICAL SEX", subtitle: "For accurate macro estimation.") {
            OptionList(options: ["Male", "Female"], selected: $sex)
            
            if sex == "Female" {
                VStack(alignment: .leading, spacing: 12) {
                    Text("STATUS (OPTIONAL)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.gray)
                    OptionList(options: ["None", "Pregnant", "Postpartum"], selected: $pregnancyStatus)
                }
                .padding(.top, 20)
                .transition(.opacity)
            }
            
            NextButton(action: onNext, isDisabled: false)
        }
    }
}

// MARK: - Step 3: Lifestyle
struct LifestyleStep: View {
    @Binding var selected: String
    let onNext: () -> Void
    let options = ["Not Active", "Medium", "Active"]
    
    var body: some View {
        StepContainer(title: "LIFESTYLE", subtitle: "How much do you move daily?") {
            OptionList(options: options, selected: $selected)
            NextButton(action: onNext, isDisabled: false)
        }
    }
}

// MARK: - Step 4: Stats
struct StatsStep: View {
    @Binding var weightLbs: String
    @Binding var heightFt: String
    @Binding var heightIn: String
    let onNext: () -> Void
    
    var body: some View {
        StepContainer(title: "YOUR STATS", subtitle: "We need this to calculate your daily energy expenditure.") {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    SetupTextField(title: "Height (ft)", text: $heightFt, keyboardType: .numberPad)
                    SetupTextField(title: "Height (in)", text: $heightIn, keyboardType: .numberPad)
                }
                SetupTextField(title: "Current Weight (lbs)", text: $weightLbs, keyboardType: .decimalPad)
            }
            NextButton(action: onNext, isDisabled: weightLbs.isEmpty || heightFt.isEmpty || heightIn.isEmpty)
        }
    }
}

// MARK: - Step 5: Location
struct LocationStep: View {
    @Binding var location: String
    let onNext: () -> Void
    
    var body: some View {
        StepContainer(title: "LOCATION", subtitle: "Where are you hunting from? (e.g. Texas, USA)") {
            SetupTextField(title: "Location", text: $location, keyboardType: .default)
            NextButton(action: onNext, isDisabled: location.isEmpty)
        }
    }
}

// MARK: - Step 6: Diet
struct DietStep: View {
    @Binding var selected: String
    let onFinish: () -> Void
    let options = ["Carnivore", "Animal-Based", "Keto", "Paleo"]
    
    var body: some View {
        StepContainer(title: "PROTOCOL", subtitle: "Select your dietary framework.") {
            OptionList(options: options, selected: $selected)
            
            Button(action: onFinish) {
                Text("FINISH SETUP")
                    .font(.system(size: 16, weight: .bold))
                    .tracking(2)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .cornerRadius(12)
            }
            .padding(.top, 24)
        }
    }
}

// MARK: - Shared UI Components

struct StepContainer<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content
    
    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 32, weight: .heavy))
                    .tracking(2)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
            
            VStack(spacing: 16) {
                content
            }
            .padding(.horizontal, 24)
        }
    }
}

struct OptionList: View {
    let options: [String]
    @Binding var selected: String
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(options, id: \.self) { option in
                Button(action: {
                    selected = option
                }) {
                    Text(option.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(selected == option ? .black : .white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(selected == option ? Color.white : Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.white.opacity(selected == option ? 0 : 0.3), lineWidth: 1)
                        )
                        .cornerRadius(12)
                }
            }
        }
    }
}

struct NextButton: View {
    let action: () -> Void
    let isDisabled: Bool
    
    var body: some View {
        Button(action: action) {
            Text("NEXT")
                .font(.system(size: 16, weight: .bold))
                .tracking(2)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .cornerRadius(12)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
        .padding(.top, 24)
    }
}

struct SetupTextField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundColor(.gray)
            
            TextField("", text: $text)
                .keyboardType(keyboardType)
                .padding()
                .foregroundColor(.white)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
        }
    }
}
