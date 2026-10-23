import SwiftUI

/// Explains what Vitalis reads from and writes to Apple Health before the system permission sheet appears,
/// so the request has context and can be declined without consequence.
struct HealthPrimingView: View {
    /// Set when profile setup finishes; cleared once the person connects or chooses "Not now".
    static let pendingKey = "healthPrimingPending"

    let onDone: () -> Void
    @State private var isRequesting = false

    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "heart.text.square")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundColor(.ncPrimary)
                            .accessibilityHidden(true)
                        Text("Connect Apple Health")
                            .font(.ui(size: 28, weight: .bold)).foregroundColor(.ncPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("Optional. You can change what's shared at any time in the Health app.")
                            .font(.ui(size: 15)).foregroundColor(.ncSecondary)
                    }

                    section("Vitalis reads", [
                        ("figure.walk", "Activity", "Steps, active energy and time in daylight, to adjust your calorie target and the Sun screen."),
                        ("heart", "Body and heart", "Weight, body fat, waist, blood pressure, resting heart rate, heart rate variability and blood glucose, shown next to your diet in Biomarkers."),
                    ])
                    section("Vitalis saves", [
                        ("fork.knife", "What you log", "Calories, protein and water, so other apps see your intake."),
                    ])

                    Label {
                        Text("Health data stays on your iPhone. It isn't uploaded to our servers, used for advertising or sold.")
                    } icon: {
                        Image(systemName: "lock")
                    }
                    .font(.ui(size: 13)).foregroundColor(.ncSecondary)

                    VStack(spacing: 8) {
                        Button {
                            isRequesting = true
                            Task {
                                try? await HealthKitManager.shared.requestAuthorization()
                                isRequesting = false
                                onDone()
                            }
                        } label: {
                            if isRequesting { ProgressView().tint(.ncOnPrimary) } else { Text("Connect Apple Health") }
                        }
                        .buttonStyle(.vitalis)
                        .disabled(isRequesting)

                        Button("Not now", action: onDone)
                            .buttonStyle(TextButtonStyle(height: 48))
                            .frame(maxWidth: .infinity)
                            .disabled(isRequesting)
                    }
                }
                .padding(Space.margin)
                .padding(.top, 24)
            }
        }
        .interactiveDismissDisabled(isRequesting)
    }

    private func section(_ title: String, _ rows: [(icon: String, title: String, detail: String)]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: title)
            ForEach(rows, id: \.title) { row in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Image(systemName: row.icon)
                        .font(.ui(size: 17)).foregroundColor(.ncPrimary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title).font(.ui(size: 15, weight: .bold)).foregroundColor(.ncPrimary)
                        Text(row.detail).font(.ui(size: 14)).foregroundColor(.ncSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
