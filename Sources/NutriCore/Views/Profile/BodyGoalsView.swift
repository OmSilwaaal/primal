import SwiftUI
import SwiftData

/// Body measurements and activity level, which drive the daily calorie and nutrient goals.
struct BodyGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    private let activityLevels = ["sedentary", "light", "moderate", "active", "veryActive"]

    var body: some View {
        ZStack {
            AppBackdrop()
            if let profile = profiles.first {
                Form {
                    Section("Body") {
                        stepperRow("Weight", value: Binding(get: { profile.weightKg }, set: { profile.weightKg = $0 }),
                                   range: 30...250, step: 0.5, unit: "kg")
                        stepperRow("Height", value: Binding(get: { profile.heightCm }, set: { profile.heightCm = $0 }),
                                   range: 100...230, step: 1, unit: "cm")
                        stepperRow("Goal weight", value: Binding(get: { profile.goalWeightKg }, set: { profile.goalWeightKg = $0 }),
                                   range: 30...250, step: 0.5, unit: "kg")
                        Stepper(value: Binding(get: { profile.age }, set: { profile.age = $0 }), in: 13...100) {
                            HStack { Text("Age"); Spacer(); Text("\(profile.age)").foregroundColor(.ncSecondary) }
                        }
                        Picker("Sex", selection: Binding(get: { profile.isMale ? "Male" : "Female" }, set: { profile.sex = $0 })) {
                            Text("Male").tag("Male")
                            Text("Female").tag("Female")
                        }
                    }
                    Section("Activity") {
                        Picker("Activity level", selection: Binding(get: { profile.activityLevel }, set: { profile.activityLevel = $0 })) {
                            ForEach(activityLevels, id: \.self) { Text($0.activityDisplayName).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    Section {
                        HStack {
                            Text("Daily calorie goal")
                            Spacer()
                            Text("\(Int(profile.dailyCalorieGoal)) kcal").foregroundColor(.ncSecondary)
                        }
                    } footer: {
                        Text("Calculated from the Mifflin-St Jeor formula using the values above.")
                    }
                }
                .scrollContentBackground(.hidden)
                .onDisappear { try? modelContext.save() }
            } else {
                EmptyState(icon: "person.crop.circle.badge.exclamationmark", title: "No profile yet",
                           message: "Finish the setup flow to add your body details.")
            }
        }
        .navigationTitle("Body & goals")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stepperRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: step < 1 ? "%.1f %@" : "%.0f %@", value.wrappedValue, unit)).foregroundColor(.ncSecondary)
            }
        }
    }
}
