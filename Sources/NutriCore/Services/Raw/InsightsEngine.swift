import Foundation

struct Insight: Identifiable {
    let id = UUID()
    let outcome: String
    let condition: String
    let withAvg: Double
    let withoutAvg: Double
    let withDays: Int
    let withoutDays: Int
    let lagged: Bool
    var diff: Double { withAvg - withoutAvg }
    var text: String {
        let when = lagged ? "the day after \(condition)" : "days with \(condition)"
        return "\(outcome) averages \(String(format: "%.1f", withAvg)) on \(when), vs \(String(format: "%.1f", withoutAvg)) otherwise."
    }
}

/// Finds simple differences between days; these are patterns in your own logs, not proof of cause.
enum InsightsEngine {
    private struct Day {
        var date: Date
        var meals: [MealEntry] = []
        var outcome: OutcomeLog?
        var sunMin: Double = 0
        var addedSodium: Double = 0
    }

    private struct Hypothesis {
        let label: String
        let test: (Day) -> Bool
    }

    static func compute(meals: [MealEntry], outcomes: [OutcomeLog], sun: [SunSession], hydration: [DailyHydration]) -> [Insight] {
        let cal = Calendar.current
        var days: [Date: Day] = [:]
        for m in meals { let d = cal.startOfDay(for: m.date); days[d, default: Day(date: d)].meals.append(m) }
        for o in outcomes { let d = cal.startOfDay(for: o.date); days[d, default: Day(date: d)].outcome = o }
        for s in sun { let d = cal.startOfDay(for: s.start); days[d, default: Day(date: d)].sunMin += s.minutes }
        for h in hydration { let d = cal.startOfDay(for: h.date); days[d, default: Day(date: d)].addedSodium += h.addedSodiumMg }

        let hyps: [Hypothesis] = [
            Hypothesis(label: "over 150 g fat") { $0.meals.totalFat > 150 },
            Hypothesis(label: "over 150 g protein") { $0.meals.totalProtein > 150 },
            Hypothesis(label: "organ meat") { $0.meals.contains { $0.cutCategory == CutCategory.organ.rawValue } },
            Hypothesis(label: "mostly raw food") { d in
                let t = d.meals.totalCalories
                return t > 0 && d.meals.reduce(0) { $0 + $1.calories * DietRater.rawness(of: $1) } / t >= 0.5
            },
            Hypothesis(label: "ground pork") { $0.meals.contains { $0.species == RawSpecies.pork.rawValue && $0.isGround } },
            Hypothesis(label: "ground meat") { $0.meals.contains { $0.isGround } },
            Hypothesis(label: "poultry") { $0.meals.contains { $0.species == RawSpecies.poultry.rawValue } },
            Hypothesis(label: "fish or shellfish") { $0.meals.contains { $0.species == RawSpecies.fish.rawValue || $0.species == RawSpecies.shellfish.rawValue } },
            Hypothesis(label: "30+ minutes outdoors") { $0.sunMin >= 30 },
            Hypothesis(label: "added salt or electrolytes") { $0.addedSodium >= 400 },
            Hypothesis(label: "a single meal") { d in DietRater.sittingCount(d.meals) == 1 },
        ]

        let metrics: [(String, (OutcomeLog) -> Double?)] = [
            ("Energy", { $0.energy > 0 ? Double($0.energy) : nil }),
            ("Mood", { $0.mood > 0 ? Double($0.mood) : nil }),
            ("Focus", { $0.focus > 0 ? Double($0.focus) : nil }),
            ("Sleep quality", { $0.sleep > 0 ? Double($0.sleep) : nil }),
            ("Satiety", { $0.satiety > 0 ? Double($0.satiety) : nil }),
            ("Digestion", { $0.bristol > 0 ? max(1, 5 - abs(Double($0.bristol) - 3.5) * 1.5) : nil }),
        ]

        var out: [Insight] = []
        for h in hyps {
            for (name, value) in metrics {
                for lag in [0, 1] {
                    if lag == 1 && name != "Digestion" { continue }
                    var with: [Double] = [], without: [Double] = []
                    for day in days.values {
                        let outcomeDay = cal.date(byAdding: .day, value: lag, to: day.date) ?? day.date
                        guard !day.meals.isEmpty || lag == 0,
                              let o = days[outcomeDay]?.outcome, let v = value(o) else { continue }
                        if h.test(day) { with.append(v) } else { without.append(v) }
                    }
                    guard with.count >= 3, without.count >= 3 else { continue }
                    let a = with.reduce(0, +) / Double(with.count), b = without.reduce(0, +) / Double(without.count)
                    if abs(a - b) >= 0.4 {
                        out.append(Insight(outcome: name, condition: h.label, withAvg: a, withoutAvg: b,
                                           withDays: with.count, withoutDays: without.count, lagged: lag == 1))
                    }
                }
            }
        }
        return out.sorted { abs($0.diff) > abs($1.diff) }
    }
}

extension DietRater {
    /// Number of separate sittings (entries within 45 minutes count as one).
    static func sittingCount(_ meals: [MealEntry]) -> Int {
        var n = 0; var last: Date?
        for d in meals.map(\.date).sorted() { if last == nil || d.timeIntervalSince(last!) > 45 * 60 { n += 1 }; last = d }
        return n
    }
}
