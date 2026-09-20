import SwiftUI
import SwiftData

struct ProfileSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    @State private var age: String = ""
    @State private var weight: String = ""
    @State private var goalWeight: String = ""
    @State private var selectedDiet = "Carnivore"
    
    let diets = ["Carnivore", "Animal-Based", "Keto", "Paleo"]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Text("YOUR PRIMAL PROTOCOL")
                        .font(.system(size: 24, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("Let's calibrate your macros before we begin.")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
                
                VStack(spacing: 20) {
                    SetupTextField(title: "Age", text: $age, keyboardType: .numberPad)
                    SetupTextField(title: "Current Weight (lbs)", text: $weight, keyboardType: .decimalPad)
                    SetupTextField(title: "Goal Weight (lbs)", text: $goalWeight, keyboardType: .decimalPad)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DIET TYPE")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1)
                            .foregroundColor(.gray)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(diets, id: \.self) { diet in
                                    Button(action: {
                                        selectedDiet = diet
                                    }) {
                                        Text(diet.uppercased())
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(selectedDiet == diet ? .black : .white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(selectedDiet == diet ? Color.white : Color.black)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                            )
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                Button(action: saveProfileAndContinue) {
                    Text("FINISH SETUP")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(2)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .cornerRadius(12)
                }
                .disabled(age.isEmpty || weight.isEmpty || goalWeight.isEmpty)
                .opacity((age.isEmpty || weight.isEmpty || goalWeight.isEmpty) ? 0.5 : 1.0)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func saveProfileAndContinue() {
        let currentWLbs = Double(weight) ?? 150.0
        let goalWLbs = Double(goalWeight) ?? 150.0
        
        let profile = UserProfile()
        profile.weightKg = currentWLbs / 2.20462
        profile.goalWeightKg = goalWLbs / 2.20462
        profile.dietType = selectedDiet
        
        modelContext.insert(profile)
        try? modelContext.save()
        
        // Mark onboarding as complete to route to Dashboard
        hasCompletedOnboarding = true
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
                .cornerRadius(8)
        }
    }
}
