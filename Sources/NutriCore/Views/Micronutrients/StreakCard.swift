import SwiftUI

/// The daily streak in one glass card: "DAILY STREAK" over the days in a row, and seven small bars for the last week
/// (Moss when intake was in range of the calorie goal, an outline when not) with "IN RANGE · N OF 7".
struct StreakCard: View {
    let streak: StreakSummary

    var body: some View {
        let inRange = streak.week.filter { $0 }.count
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily streak").font(.mono(11, .semibold)).tracking(0.88).textCase(.uppercase)
                    .foregroundColor(Mono.label)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(streak.days)").font(.display(40)).foregroundColor(.white)
                        .contentTransition(.numericText())
                    Text(streak.days == 1 ? "day" : "days").font(.ui(size: 17, weight: .semibold)).foregroundColor(.white)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(streak.week.enumerated()), id: \.offset) { _, on in
                        Group {
                            if on {
                                Capsule().fill(Color.ncMoss)
                            } else {
                                Capsule().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.2)
                            }
                        }
                        .frame(width: 8, height: 30)
                    }
                }
                Text("In range · \(inRange) of 7").font(.mono(11, .semibold)).tracking(0.66).textCase(.uppercase)
                    .foregroundColor(Mono.label)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .glassSheen(in: shape, strength: 0.7)
        .glass(.clear, in: shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily streak, \(streak.days) day\(streak.days == 1 ? "" : "s")")
        .accessibilityValue("In range \(inRange) of the last 7 days")
    }
}

#if DEBUG
#Preview("Streak") {
    StreakCard(streak: DataPreview.streak)
        .padding()
        .background(Color(hex: "#08090A"))
        .preferredColorScheme(.dark)
}
#endif
