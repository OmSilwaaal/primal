import SwiftUI
import SwiftData

/// The Data tab: vitamins and minerals against the daily targets, for today or as a daily average over the last
/// week. A large diet-score tile, then a two-column grid of nutrient tiles: percent, bar and a Low / On track / Done
/// pill (Low is under 60% of the target).
struct MicronutrientsView: View {
    enum Range: Hashable { case today, week }

    @Query private var meals: [MealEntry]
    @Query private var profiles: [UserProfile]
    @State private var range: Range = .today

    /// The key nutrients, shown first in this order; the rest follow, lowest first.
    private static let featured = ["vd", "mg", "fe", "ca", "vc", "b12"]

    init() {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: .now)) ?? .now
        _meals = Query(filter: #Predicate<MealEntry> { $0.date >= start })
    }

    private var goals: NutrientGoals { profiles.first.map(NutrientGoals.from) ?? .default }

    private var rangeMeals: [MealEntry] {
        range == .today ? meals.filter { Calendar.current.isDateInToday($0.date) } : meals
    }

    /// Days with anything logged in the range, so a week average isn't dragged down by days before you started.
    private var loggedDays: Double {
        let cal = Calendar.current
        return Double(max(1, Set(rangeMeals.map { cal.startOfDay(for: $0.date) }).count))
    }

    /// Vitamins and minerals: today's totals, or the daily average over the week's logged days.
    private var nutrients: [NutrientInfo] {
        let days = range == .today ? 1 : loggedDays
        return buildNutrientList(from: rangeMeals, goals: goals)
            .filter { $0.group != .macros }
            .map { NutrientInfo(id: $0.id, name: $0.name, unit: $0.unit, icon: $0.icon, group: $0.group,
                                current: $0.current / days, goal: $0.goal) }
    }

    var body: some View {
        let all = nutrients
        let featured = Self.featured.compactMap { id in all.first { $0.id == id } }
        let rest = all.filter { !Self.featured.contains($0.id) }.sorted { $0.progress < $1.progress }

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Bento.gap) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Nutrients").font(.bentoTitle).foregroundColor(Mono.text)
                        .accessibilityAddTraits(.isHeader)
                    BentoSegmented(options: [(.today, "Today"), (.week, "Week")], selection: $range)
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                ScoreTile(nutrients: all, range: range, hasMeals: !rangeMeals.isEmpty)

                grid(featured)

                if !rest.isEmpty {
                    Text("More nutrients").font(.bentoLabel).foregroundColor(Mono.label)
                        .padding(.top, 12).padding(.leading, 4)
                        .accessibilityAddTraits(.isHeader)
                    grid(rest)
                }

                Text("Daily targets follow NIH dietary reference intakes for your age and sex."
                     + (range == .week ? " Week shows the daily average over days you logged." : ""))
                    .font(.ui(size: 12)).lineSpacing(3).foregroundColor(Mono.label)
                    .padding(.top, 8).padding(.horizontal, 4)
            }
            .padding(.horizontal, Bento.margin)
            .padding(.bottom, 120)
            .animation(.smooth(duration: 0.3), value: range)
        }
        .glassLightFollowsScroll()
    }

    /// Tiles two to a row.
    private func grid(_ items: [NutrientInfo]) -> some View {
        VStack(spacing: Bento.gap) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                BentoPair {
                    tile(items[i])
                } right: {
                    if i + 1 < items.count { tile(items[i + 1]) } else { Color.clear.frame(maxWidth: .infinity) }
                }
            }
        }
    }

    private func tile(_ n: NutrientInfo) -> some View {
        let raw = n.goal > 0 ? n.current / n.goal : 0
        return BentoTile(title: n.name, value: "\(Int((min(raw, 9.99) * 100).rounded()))%", progress: raw,
                         status: BentoStatus(progress: raw))
            .accessibilityLabel("\(n.name), \(Int((raw * 100).rounded())) percent of target")
    }
}

/// The large tile: a 0–100 diet score (average share of each nutrient's target met, capped at 100% each) and one
/// line on what's holding it back.
private struct ScoreTile: View {
    let nutrients: [NutrientInfo]
    let range: MicronutrientsView.Range
    let hasMeals: Bool

    private var score: Int {
        guard !nutrients.isEmpty else { return 0 }
        return Int((nutrients.map(\.progress).reduce(0, +) / Double(nutrients.count) * 100).rounded())
    }

    private var note: String {
        let when = range == .today ? "today" : "this week"
        guard hasMeals else { return "Log a meal to see your score \(when)." }
        let low = nutrients.filter { $0.goal > 0 && $0.current / $0.goal < 0.6 }
        guard let lowest = nutrients.min(by: { $0.progress < $1.progress }), !low.isEmpty else {
            return "Nothing is low \(when)."
        }
        return "\(low.count) low \(when). Lowest is \(lowest.name) at \(lowest.percentage)%."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diet score").font(.bentoLabel).foregroundColor(Mono.label)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(score)").font(.bentoNumber(64)).tracking(Font.bentoTracking(64)).foregroundColor(Mono.text)
                    .contentTransition(.numericText())
                Text("/ 100").font(.ui(size: 17, weight: .medium)).foregroundColor(Mono.label)
            }
            BentoBar(value: Double(score) / 100)
            Text(note).font(.bentoBody).foregroundColor(Mono.label)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .bentoTile(padding: 18)
        .accessibilityElement(children: .combine)
    }
}
