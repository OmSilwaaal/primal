import Foundation

struct LiverBudget {
    var avgVitaminA: Double      // mcg RAE per day over the window
    var avgCopper: Double        // mg per day
    var weeklyVitaminA: Double
    var remainingVitaminAWeek: Double
    var beefLiverGramsLeft: Double

    static let vitaminAUL = 3000.0    // mcg RAE/day, adult UL (preformed)
    static let copperUL = 10.0        // mg/day, adult UL

    var vitaminAPct: Double { avgVitaminA / Self.vitaminAUL }
    var copperPct: Double { avgCopper / Self.copperUL }
    var status: BudgetStatus {
        let worst = max(vitaminAPct, copperPct)
        return worst >= 1 ? .over : worst >= 0.8 ? .approaching : .ok
    }
}

enum BudgetStatus { case ok, approaching, over }

struct NutrientGap: Identifiable {
    var id: String { name }
    let name: String
    let avg: Double
    let target: Double
    let unit: String
    var pct: Double { target > 0 ? avg / target : 0 }
}

struct OrganStatus: Identifiable {
    var id: String { organ.rawValue }
    let organ: Organ
    let lastEaten: Date?
    let weekGrams: Double
    let capGrams: Double
    let targetGapDays: Int
    var daysSince: Int? {
        guard let lastEaten else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastEaten), to: Calendar.current.startOfDay(for: Date())).day
    }
    var overCap: Bool { weekGrams > capGrams }
    var due: Bool { (daysSince ?? Int.max) >= targetGapDays }
}

enum NutrientAnalyzer {
    static func window(_ meals: [MealEntry], days: Int, now: Date = Date()) -> [MealEntry] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now)) ?? .distantPast
        return meals.filter { $0.date >= cutoff }
    }

    /// Fat share of macro calories (4/4/9). Nil when nothing is logged.
    static func fatCaloriePct(_ meals: [MealEntry]) -> Double? {
        let f = meals.totalFat * 9, p = meals.totalProtein * 4, c = meals.totalCarbs * 4
        let t = f + p + c
        return t > 0 ? f / t * 100 : nil
    }

    static func liverBudget(_ meals: [MealEntry], now: Date = Date()) -> LiverBudget {
        let w = window(meals, days: 7, now: now)
        let weekA = w.totalVitaminA
        let remaining = max(0, LiverBudget.vitaminAUL * 7 - weekA)
        // Beef liver ≈ 4,970 mcg RAE per 100 g.
        return LiverBudget(avgVitaminA: weekA / 7, avgCopper: w.totalCopper / 7, weeklyVitaminA: weekA,
                           remainingVitaminAWeek: remaining, beefLiverGramsLeft: remaining / 49.7)
    }

    static func omegaRatio(_ meals: [MealEntry]) -> Double? {
        meals.totalOmega3 > 0.01 ? meals.totalOmega6 / meals.totalOmega3 : nil
    }

    /// Per-day averages over days that have any logged food, compared with general RDA values.
    static func gaps(_ meals: [MealEntry], goals: NutrientGoals, male: Bool, days: Int = 7) -> (gaps: [NutrientGap], loggedDays: Int) {
        let w = window(meals, days: days)
        let cal = Calendar.current
        let loggedDays = max(1, Set(w.map { cal.startOfDay(for: $0.date) }).count)
        func avg(_ v: Double) -> Double { v / Double(loggedDays) }
        let list: [NutrientGap] = [
            NutrientGap(name: "Vitamin A", avg: avg(w.totalVitaminA), target: goals.vitaminA, unit: "mcg"),
            NutrientGap(name: "Vitamin C", avg: avg(w.totalVitaminC), target: goals.vitaminC, unit: "mg"),
            NutrientGap(name: "Vitamin D", avg: avg(w.totalVitaminD), target: goals.vitaminD, unit: "mcg"),
            NutrientGap(name: "Vitamin E", avg: avg(w.totalVitaminE), target: goals.vitaminE, unit: "mg"),
            NutrientGap(name: "Vitamin B12", avg: avg(w.totalVitaminB12), target: goals.vitaminB12, unit: "mcg"),
            NutrientGap(name: "Folate", avg: avg(w.totalFolate), target: goals.folate, unit: "mcg"),
            NutrientGap(name: "Choline", avg: avg(w.totalCholine), target: male ? 550 : 425, unit: "mg"),
            NutrientGap(name: "Calcium", avg: avg(w.totalCalcium), target: goals.calcium, unit: "mg"),
            NutrientGap(name: "Magnesium", avg: avg(w.totalMagnesium), target: goals.magnesium, unit: "mg"),
            NutrientGap(name: "Potassium", avg: avg(w.totalPotassium), target: goals.potassium, unit: "mg"),
            NutrientGap(name: "Iron", avg: avg(w.totalIron), target: goals.iron, unit: "mg"),
            NutrientGap(name: "Zinc", avg: avg(w.totalZinc), target: goals.zinc, unit: "mg"),
            NutrientGap(name: "Selenium", avg: avg(w.totalSelenium), target: goals.selenium, unit: "mcg"),
            NutrientGap(name: "Copper", avg: avg(w.totalCopper), target: goals.copper, unit: "mg"),
            NutrientGap(name: "Iodine", avg: avg(w.totalIodine), target: 150, unit: "mcg"),
        ]
        return (list, w.isEmpty ? 0 : loggedDays)
    }

    /// Calcium and vitamin C are flagged when they sit under half the reference on most logged days.
    static func chronicLow(_ meals: [MealEntry], goals: NutrientGoals) -> [String] {
        let w = window(meals, days: 14)
        let cal = Calendar.current
        let byDay = Dictionary(grouping: w) { cal.startOfDay(for: $0.date) }
        guard byDay.count >= 4 else { return [] }
        var out: [String] = []
        let lowC = byDay.values.filter { $0.totalCalcium < goals.calcium * 0.5 }.count
        let lowVC = byDay.values.filter { $0.totalVitaminC < goals.vitaminC * 0.5 }.count
        if Double(lowC) / Double(byDay.count) >= 0.75 { out.append("Calcium") }
        if Double(lowVC) / Double(byDay.count) >= 0.75 { out.append("Vitamin C") }
        return out
    }

    // MARK: Organ rotation
    static let organCapG: [Organ: Double] = [.liver: 300, .kidney: 300, .spleen: 200, .brain: 100, .heart: 700, .marrow: 400]
    static let organGapDays: [Organ: Int] = [.liver: 7, .kidney: 10, .heart: 5, .spleen: 14, .brain: 14, .marrow: 7]

    static func organStatus(_ meals: [MealEntry]) -> [OrganStatus] {
        let week = window(meals, days: 7)
        return Organ.allCases.map { o in
            let all = meals.filter { $0.cutCategory == CutCategory.organ.rawValue && $0.organType == o.rawValue }
            return OrganStatus(organ: o, lastEaten: all.map(\.date).max(),
                               weekGrams: week.filter { $0.organType == o.rawValue }.reduce(0) { $0 + $1.servingSize },
                               capGrams: organCapG[o] ?? 300, targetGapDays: organGapDays[o] ?? 7)
        }
    }

    // MARK: Meal timing
    struct Timing { let mealsPerDay: Double; let windowHours: Double; let pattern: String }
    static func timing(_ meals: [MealEntry], days: Int = 7) -> Timing? {
        let w = window(meals, days: days)
        let cal = Calendar.current
        let byDay = Dictionary(grouping: w) { cal.startOfDay(for: $0.date) }
        guard !byDay.isEmpty else { return nil }
        // Entries within 45 minutes belong to the same sitting.
        func sittings(_ ms: [MealEntry]) -> Int {
            let sorted = ms.map(\.date).sorted()
            var n = 0; var last: Date?
            for d in sorted { if last == nil || d.timeIntervalSince(last!) > 45 * 60 { n += 1 }; last = d }
            return n
        }
        let counts = byDay.values.map(sittings)
        let avgMeals = Double(counts.reduce(0, +)) / Double(counts.count)
        let windows = byDay.values.map { ms -> Double in
            let d = ms.map(\.date)
            return (d.max()!.timeIntervalSince(d.min()!)) / 3600
        }
        let pattern = avgMeals <= 1.3 ? "OMAD" : avgMeals <= 2.3 ? "2MAD" : "3+ meals"
        return Timing(mealsPerDay: avgMeals, windowHours: windows.reduce(0, +) / Double(windows.count), pattern: pattern)
    }
}
