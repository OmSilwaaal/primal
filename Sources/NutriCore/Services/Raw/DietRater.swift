import Foundation

enum DietTier: String {
    case insufficient, omnivore, animalForward, animalBased, carnivoreDairyEggs
    case cookedCarnivore, partRawCarnivore, mostlyRawCarnivore, rawCarnivore

    var title: String {
        switch self {
        case .insufficient: "Not enough data"
        case .omnivore: "Omnivore"
        case .animalForward: "Animal-forward"
        case .animalBased: "Animal-based"
        case .carnivoreDairyEggs: "Carnivore + dairy & eggs"
        case .cookedCarnivore: "Strict carnivore (cooked)"
        case .partRawCarnivore: "Part-raw carnivore"
        case .mostlyRawCarnivore: "Mostly raw carnivore"
        case .rawCarnivore: "Raw carnivore"
        }
    }
    var blurb: String {
        switch self {
        case .insufficient: "Log a few meals and your position will appear here."
        case .omnivore: "Plant foods supply most of your calories."
        case .animalForward: "Animal foods lead, with a large share of plants."
        case .animalBased: "Mostly animal foods with a modest plant share (fruit, honey, etc.)."
        case .carnivoreDairyEggs: "Animal foods only, with a notable dairy and egg share."
        case .cookedCarnivore: "Meat, organs and fat — almost all cooked."
        case .partRawCarnivore: "Carnivore with some raw or rare food."
        case .mostlyRawCarnivore: "Carnivore with raw food making up a large share."
        case .rawCarnivore: "Carnivore with nearly everything eaten raw."
        }
    }
}

struct DietRating {
    var days: Int
    var kcal: Double
    var mealCount: Int
    var rawPct: Double         // 0…100 of calories
    var animalPct: Double      // meat, fish, organs, fat, dairy, eggs
    var strictPct: Double      // meat, fish, organs, fat only
    var dairyEggPct: Double
    var plantPct: Double
    var cookedAnimalPct: Double
    var avgCarbsG: Double
    var tier: DietTier
    var position: Double       // 0…1 along Omnivore → Raw carnivore
    var steps: [String]
}

enum DietRater {
    private static let dairyEgg = ["egg", "milk", "cheese", "butter", "cream", "yogurt", "yoghurt", "kefir", "ghee", "whey", "curd"]
    private static let meat = ["beef", "steak", "ribeye", "sirloin", "brisket", "burger", "mince", "chuck", "veal", "lamb", "mutton",
                               "pork", "bacon", "ham", "sausage", "chicken", "turkey", "duck", "goose", "bison", "venison", "elk", "deer",
                               "rabbit", "liver", "heart", "kidney", "tongue", "tripe", "bone marrow", "marrow", "tallow", "suet", "lard",
                               "salmon", "tuna", "cod", "trout", "sardine", "mackerel", "herring", "fish", "shrimp", "prawn", "oyster",
                               "crab", "lobster", "scallop", "clam", "mussel", "roe", "jerky", "meat", "organ"]

    enum Kind { case strict, dairyEgg, plant }

    static func kind(of meal: MealEntry) -> Kind {
        if !meal.species.isEmpty { return .strict }
        let n = meal.foodName.lowercased()
        // Match whole words so "ham" doesn't hit "hamburger bun" style names too eagerly.
        let words = Set(n.split(whereSeparator: { !$0.isLetter }).map(String.init))
        func has(_ keys: [String]) -> Bool {
            keys.contains { $0.contains(" ") ? n.contains($0) : (words.contains($0) || words.contains($0 + "s")) }
        }
        if has(meat) && !has(["bun", "bread", "pizza", "pasta", "noodle", "rice", "sandwich", "cracker", "oil"]) { return .strict }
        if has(dairyEgg) && !has(["bread", "cake", "cookie", "chocolate", "ice", "pasta", "noodle", "sandwich"]) { return .dairyEgg }
        return .plant
    }

    static func rawness(of meal: MealEntry) -> Double {
        if let p = Prep(rawValue: meal.prep) { return p.rawness }
        let n = meal.foodName.lowercased()
        if n.contains("raw") || n.contains("tartare") || n.contains("carpaccio") || n.contains("sashimi") || n.contains("ceviche") { return 1 }
        if n.contains("rare") { return 0.5 }
        return 0
    }

    static func rate(meals: [MealEntry], days: Int, now: Date = Date()) -> DietRating {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: now)) ?? .distantPast
        let window = meals.filter { $0.date >= cutoff && $0.calories > 0 }
        let total = window.totalCalories

        var raw = 0.0, strict = 0.0, de = 0.0, plant = 0.0
        for m in window {
            switch kind(of: m) {
            case .strict: strict += m.calories; raw += m.calories * rawness(of: m)
            case .dairyEgg:
                de += m.calories
                if m.foodName.lowercased().contains("raw") { raw += m.calories }
            case .plant: plant += m.calories
            }
        }
        let pct: (Double) -> Double = { total > 0 ? $0 / total * 100 : 0 }
        let rawPct = pct(raw), strictPct = pct(strict), dePct = pct(de), plantPct = pct(plant)
        let animalPct = strictPct + dePct
        let carbDays = Set(window.map { cal.startOfDay(for: $0.date) }).count
        let avgCarbs = carbDays > 0 ? window.totalCarbs / Double(carbDays) : 0

        let tier: DietTier
        if total < 400 { tier = .insufficient }
        else if plantPct >= 45 { tier = .omnivore }
        else if plantPct >= 25 { tier = .animalForward }
        else if plantPct >= 8 { tier = .animalBased }
        else if dePct >= 15 { tier = .carnivoreDairyEggs }
        else if rawPct >= 80 { tier = .rawCarnivore }
        else if rawPct >= 40 { tier = .mostlyRawCarnivore }
        else if rawPct >= 10 { tier = .partRawCarnivore }
        else { tier = .cookedCarnivore }

        let position = total < 400 ? 0 : min(1, max(0, 0.5 * ((animalPct / 100 - 0.4) / 0.6) + 0.5 * (rawPct / 100)))

        var steps: [String] = []
        if tier != .insufficient {
            if plantPct >= 8 { steps.append("Plant foods are \(Int(plantPct))% of your calories. Under about 8% places you in the carnivore range.") }
            if dePct >= 15 && plantPct < 8 { steps.append("Dairy and eggs are \(Int(dePct))% of calories; dropping below 15% puts you in strict carnivore.") }
            if rawPct < 80 && plantPct < 25 {
                let cookedAnimal = max(0, strictPct - rawPct)
                steps.append("\(Int(cookedAnimal))% of calories are cooked animal foods. Raw-carnivore territory starts around 80% raw.")
            }
            if rawPct >= 80 { steps.append("Nearly everything you log is raw — the food-safety score matters most at this end of the spectrum.") }
        }

        return DietRating(days: days, kcal: total, mealCount: window.count, rawPct: rawPct, animalPct: animalPct,
                          strictPct: strictPct, dairyEggPct: dePct, plantPct: plantPct,
                          cookedAnimalPct: max(0, strictPct - rawPct), avgCarbsG: avgCarbs,
                          tier: tier, position: position, steps: steps)
    }
}
