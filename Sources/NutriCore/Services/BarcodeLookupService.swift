import Foundation

/// Resolves a scanned product barcode to nutrition data.
/// USDA Branded Foods is tried first (exact GTIN match only); Open Food Facts is the fallback.
@MainActor
final class BarcodeLookupService: ObservableObject {
    enum State {
        case idle
        case loading
        case found(FoodSearchResult)
        case notFound
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    func lookup(_ code: String) {
        task?.cancel()
        state = .loading
        task = Task {
            do {
                let food = try await Self.resolve(code)
                guard !Task.isCancelled else { return }
                state = food.map(State.found) ?? .notFound
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    func reset() {
        task?.cancel()
        state = .idle
    }

    // MARK: - Resolution

    private nonisolated static func resolve(_ code: String) async throws -> FoodSearchResult? {
        let wanted = normalized(code)

        // USDA failures shouldn't block the fallback.
        if let foods = try? await USDAService.fetch(query: code, dataTypes: ["Branded"], pageSize: 10),
           let match = foods.first(where: { normalized($0.gtinUpc ?? "") == wanted }) {
            return match
        }
        return try await openFoodFacts(code)
    }

    /// UPC-A (12), EAN-13 (13) and GTIN-14 differ only by leading zeros.
    private nonisolated static func normalized(_ code: String) -> String {
        String(code.drop(while: { $0 == "0" }))
    }

    private nonisolated static func openFoodFacts(_ code: String) async throws -> FoodSearchResult? {
        guard code.allSatisfy(\.isNumber),
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,nutriments,serving_quantity")
        else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Vitalis-iOS/1.0 (nutrition tracker)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["status"] as? Int) == 1,
              let product = root["product"] as? [String: Any],
              let n = product["nutriments"] as? [String: Any]
        else { return nil }

        func v(_ key: String) -> Double? {
            if let d = n[key] as? Double { return d }
            if let i = n[key] as? Int { return Double(i) }
            if let s = n[key] as? String { return Double(s) }
            return nil
        }

        // Open Food Facts reports per 100 g; minerals/vitamins in grams -> convert to the units USDA uses.
        var items: [FoodNutrientItem] = []
        func add(_ id: Int, _ value: Double?, scale: Double = 1) {
            if let value { items.append(FoodNutrientItem(nutrientId: id, value: value * scale)) }
        }
        let kcal = v("energy-kcal_100g") ?? v("energy_100g").map { $0 / 4.184 }
        add(1008, kcal)
        add(1003, v("proteins_100g"))
        add(1005, v("carbohydrates_100g"))
        add(1004, v("fat_100g"))
        add(1079, v("fiber_100g"))
        add(2000, v("sugars_100g"))
        add(1258, v("saturated-fat_100g"))
        add(1253, v("cholesterol_100g"), scale: 1000)
        add(1093, v("sodium_100g") ?? v("salt_100g").map { $0 * 0.4 }, scale: 1000)
        add(1087, v("calcium_100g"), scale: 1000)
        add(1089, v("iron_100g"), scale: 1000)
        add(1092, v("potassium_100g"), scale: 1000)
        add(1090, v("magnesium_100g"), scale: 1000)
        add(1095, v("zinc_100g"), scale: 1000)
        add(1162, v("vitamin-c_100g"), scale: 1000)

        guard kcal != nil else { return nil }

        let name = (product["product_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Scanned product"
        let serving = (product["serving_quantity"] as? Double) ?? (product["serving_quantity"] as? String).flatMap(Double.init)
        return FoodSearchResult(
            fdcId: 0,
            description: name,
            dataType: "Open Food Facts",
            brandOwner: product["brands"] as? String,
            servingSize: serving,
            servingSizeUnit: serving == nil ? nil : "g",
            foodNutrients: items
        )
    }
}
