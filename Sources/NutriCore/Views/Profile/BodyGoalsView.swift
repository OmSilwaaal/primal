import SwiftUI
import SwiftData

/// Body measurements and activity level, which drive the daily calorie and nutrient goals.
struct BodyGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    private let activityLevels = ["sedentary", "light", "moderate", "active", "veryActive"]

    var body: some View {
        RawScreen(title: "Body & goals", subtitle: "Drives your daily targets") {
            if let profile = profiles.first {
                RawCard(title: "Daily goal", index: "01") {
                    VStack(alignment: .leading, spacing: 10) {
                        Metric(value: Int(profile.dailyCalorieGoal).formatted(), unit: "kcal", size: 56)
                            .animation(.smooth, value: Int(profile.dailyCalorieGoal))
                        Text("Calculated with the Mifflin-St Jeor formula from the values below.")
                            .font(.ui(size: 14)).foregroundColor(.ncSecondary)
                    }
                }

                RawCard(title: "Body", index: "02") {
                    VStack(spacing: 0) {
                        stepper("Weight", value: Binding(get: { profile.weightKg }, set: { profile.weightKg = $0 }), range: 30...250, step: 0.5, unit: "kg")
                        stepper("Goal weight", value: Binding(get: { profile.goalWeightKg }, set: { profile.goalWeightKg = $0 }), range: 30...250, step: 0.5, unit: "kg")
                        stepper("Height", value: Binding(get: { profile.heightCm }, set: { profile.heightCm = $0 }), range: 100...230, step: 1, unit: "cm")
                        stepper("Age", value: Binding(get: { Double(profile.age) }, set: { profile.age = Int($0) }), range: 13...100, step: 1, unit: "yrs")
                        HStack {
                            Text("Sex").font(.ui(size: 17)).foregroundColor(.ncPrimary)
                            Spacer()
                            ForEach(["Male", "Female"], id: \.self) { s in
                                Chip(label: s, selected: (profile.isMale ? "Male" : "Female") == s) { profile.sex = s }
                            }
                        }
                        .padding(.vertical, 14)
                    }
                }

                RawCard(title: "Activity", index: "03") {
                    OptionList(options: activityLevels.map(\.activityDisplayName),
                               selected: Binding(get: { profile.activityLevel.activityDisplayName },
                                                 set: { label in profile.activityLevel = activityLevels.first { $0.activityDisplayName == label } ?? "moderate" }))
                }
            } else {
                EmptyState(icon: "person", title: "No profile yet", message: "Finish the setup flow to add your body details.")
            }
        }
        .onDisappear { try? modelContext.save() }
    }

    private func stepper(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.ui(size: 17)).foregroundColor(.ncPrimary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: step < 1 ? "%.1f" : "%.0f", value.wrappedValue)).font(.metric(17)).foregroundColor(.ncPrimary)
                    Text(unit).font(.serif(13)).foregroundColor(.ncSecondary)
                }
                Stepper("", value: value, in: range, step: step).labelsHidden().fixedSize()
            }
            .padding(.vertical, 12)
            Hairline(opacity: 0.1)
        }
    }
}
