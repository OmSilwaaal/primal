import Foundation

/// Turns a photo's AI reading into a meal with real nutrition data.
///
/// The model (Claude Haiku 5.5, on the server) is good at *what* and *how much* (it names each food on the plate and estimates its weight) and poor at
/// micronutrients, so it only does that part. Each food is then looked up in USDA (Foundation / SR Legacy, then
/// FNDDS for mixed dishes) for its full per-100 g profile — vitamins, minerals, omega-3 and all. A match is only used
/// when its name agrees with the food, it has energy, and its kcal is within reason of the model's own estimate;
/// otherwise that food keeps the model's macros. The parts are combined into one per-100 g food, so the scan card's
/// serving control and logging work exactly as for search and barcode.
enum PhotoMeal {
    /// `FoodSearchResult.dataType` for a photo meal (shown as the meal's source).
    static let dataType = "Photo estimate"

    /// One food the model saw.
    struct Item: Codable, Equatable {
        var name: String
        /// A USDA-style description to search for, e.g. "Beef, ribeye, steak, raw".
        var usdaQuery: String
        var grams: Double
        var raw: Bool
        // The model's own estimate for this portion, used to sanity-check the USDA match and as the fallback.
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
    }

    /// What the scan card shows and logs.
    struct Result {
        let food: FoodSearchResult      // per 100 g of the whole plate
        let grams: Double               // the plate's total weight
        let items: [Item]
        /// How many items got their nutrients from USDA (the rest use the model's macros only).
        let matched: Int
    }

    // The prompt and the model call live on the server (supabase/functions/ai, SCAN_SYSTEM): the app never
    // talks to a model directly.

    // MARK: Parsing

    /// The model's text as items. Tolerates code fences and drops items without a name or weight.
    static func parse(_ text: String) throws -> [Item] {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        struct Reply: Decodable { let items: [Item] }
        let reply = try JSONDecoder().decode(Reply.self, from: Data(cleaned.utf8))
        return reply.items.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.grams > 0 }
    }

    // MARK: Matching

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "%") })
            .map { w in w.count > 3 && w.hasSuffix("s") && !w.hasSuffix("ss") ? String(w.dropLast()) : String(w) }
            .filter { !["and", "with", "the", "of", "a"].contains($0) }
    }

    /// The best USDA candidate for an item, or nil when none is trustworthy.
    static func bestMatch(for item: Item, in candidates: [FoodSearchResult]) -> FoodSearchResult? {
        let ordered = words(item.usdaQuery.isEmpty ? item.name : item.usdaQuery)
        let query = Set(ordered)
        guard let kind = ordered.first else { return nil }
        var best: (food: FoodSearchResult, score: Double)?
        for (rank, food) in candidates.enumerated() {
            let description = Set(words(food.description))
            let hit = Double(query.intersection(description).count) / Double(query.count)
            // USDA names lead with the kind of food ("Mollusks, oyster…", "Beef, liver…"): it must be there, so
            // "Mushrooms, oyster, raw" can't stand in for oysters.
            guard hit >= 0.6, description.contains(kind) else { continue }
            // Energy must be there (unless the model sees a zero-calorie item), and close to the model's estimate:
            // a 2.5× gap means the search found the wrong thing (oyster mushrooms for oysters).
            let kcal = food.energyKcal * item.grams / 100
            if food.energyKcal <= 0 && item.kcal > 5 { continue }
            if item.kcal > 20, kcal > 0, max(kcal, item.kcal) / min(kcal, item.kcal) > 2.5 { continue }
            let rawAgrees = description.contains("raw") == item.raw
            let extra = Double(description.subtracting(query).count)
            let completeness: Double = Double(min(food.nutrientCount, 100)) / 50   // SR Legacy ~100 nutrients → 2
            let rawBonus: Double = rawAgrees ? 1.5 : -1.5
            let tieBreak: Double = Double(rank) * 0.1                              // USDA's own ranking
            var score: Double = hit * 10
            score -= extra * 0.25
            score += completeness + rawBonus - tieBreak
            if best == nil || score > best!.score { best = (food, score) }
        }
        return best?.food
    }

    // MARK: Combining

    /// The plate as one food per 100 g: each nutrient is the weight-weighted sum of its parts. Items without a USDA
    /// match contribute the model's kcal and macros.
    static func combine(_ parts: [(item: Item, match: FoodSearchResult?)]) -> FoodSearchResult {
        let total = parts.reduce(0) { $0 + $1.item.grams }
        var sums: [Int: Double] = [:]
        for (item, match) in parts {
            if let match {
                let f = item.grams / 100
                for n in match.foodNutrients where n.value > 0 && n.nutrientId != 2047 && n.nutrientId != 2048 {
                    sums[n.nutrientId, default: 0] += n.value * f
                }
                // Energy under 1008 whatever ID the record used.
                if match.nutrient(1008) <= 0 { sums[1008, default: 0] += match.energyKcal * f }
            } else {
                sums[1008, default: 0] += item.kcal
                sums[1003, default: 0] += item.protein
                sums[1005, default: 0] += item.carbs
                sums[1004, default: 0] += item.fat
            }
        }
        let scale = total > 0 ? 100 / total : 0
        let nutrients = sums.map { FoodNutrientItem(nutrientId: $0.key, value: $0.value * scale) }
            .sorted { $0.nutrientId < $1.nutrientId }
        return FoodSearchResult(fdcId: 0, description: name(for: parts.map(\.item)), dataType: dataType,
                                servingSize: total, servingSizeUnit: "g", foodNutrients: nutrients)
    }

    /// "Ribeye steak + egg yolks", with ", raw" when everything on the plate is raw (so the Raw card counts it).
    static func name(for items: [Item]) -> String {
        guard let first = items.first else { return "Meal" }
        let names = ([first.name] + items.dropFirst().map { $0.name.lowercased() }).joined(separator: " + ")
        return items.allSatisfy(\.raw) && !names.lowercased().contains("raw") ? names + ", raw" : names
    }

    // MARK: Lookup

    /// Looks every item up in USDA (in parallel) and combines them.
    static func resolve(_ items: [Item]) async -> Result {
        let matches = await withTaskGroup(of: (Int, FoodSearchResult?).self) { group in
            for (i, item) in items.enumerated() {
                group.addTask {
                    let query = item.usdaQuery.isEmpty ? item.name : item.usdaQuery
                    if let whole = try? await USDAService.fetch(query: query, dataTypes: ["Foundation", "SR Legacy"], pageSize: 10),
                       let match = bestMatch(for: item, in: whole) {
                        return (i, match)
                    }
                    // Mixed and cooked dishes ("beef stew") live in FNDDS.
                    let dishes = (try? await USDAService.fetch(query: query, dataTypes: ["Survey (FNDDS)"], pageSize: 10)) ?? []
                    return (i, bestMatch(for: item, in: dishes))
                }
            }
            var found = [FoodSearchResult?](repeating: nil, count: items.count)
            for await (i, match) in group { found[i] = match }
            return found
        }
        let parts = Array(zip(items, matches)).map { (item: $0.0, match: $0.1) }
        return Result(food: combine(parts), grams: items.reduce(0) { $0 + $1.grams }, items: items,
                      matched: matches.compactMap { $0 }.count)
    }
}
