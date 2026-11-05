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

    nonisolated static func resolve(_ code: String) async throws -> FoodSearchResult? {
        let digits = expandedUPCE(code) ?? code
        let wanted = normalized(digits)

        // USDA only matches the exact form it stored (12-digit UPC-A, 13-digit EAN or 14-digit GTIN), while the
        // camera reports a US UPC-A as a 13-digit EAN with a leading 0 — so try each form until one hits.
        // USDA failures shouldn't block the fallback.
        for query in searchForms(digits) {
            if let foods = try? await USDAService.fetch(query: query, dataTypes: ["Branded"], pageSize: 5),
               let match = foods.first(where: { normalized($0.gtinUpc ?? "") == wanted }) {
                return match
            }
        }
        return try await openFoodFacts(digits)
    }

    /// UPC-A (12), EAN-13 (13) and GTIN-14 differ only by leading zeros.
    nonisolated static func normalized(_ code: String) -> String {
        String(code.drop(while: { $0 == "0" }))
    }

    /// The forms USDA might have stored a code under, most likely first: as scanned, then 12, 13 and 14 digits.
    nonisolated static func searchForms(_ code: String) -> [String] {
        let core = normalized(code)
        guard !core.isEmpty, code.allSatisfy(\.isNumber) else { return [] }
        var forms = [code]
        for length in [12, 13, 14] where core.count <= length {
            let padded = String(repeating: "0", count: length - core.count) + core
            if !forms.contains(padded) { forms.append(padded) }
        }
        return forms
    }

    /// A UPC-E code (8 digits: number system 0/1, six data digits, check digit) expanded to its 12-digit UPC-A,
    /// which is what the databases store. Nil for anything else.
    nonisolated static func expandedUPCE(_ code: String) -> String? {
        let d = Array(code)
        guard d.count == 8, code.allSatisfy(\.isNumber), d[0] == "0" || d[0] == "1" else { return nil }
        let ns = String(d[0]), check = String(d[7])
        let x = d[1...6].map(String.init)
        let body: String
        switch x[5] {
        case "0", "1", "2": body = x[0] + x[1] + x[5] + "0000" + x[2] + x[3] + x[4]
        case "3": body = x[0] + x[1] + x[2] + "00000" + x[3] + x[4]
        case "4": body = x[0] + x[1] + x[2] + x[3] + "00000" + x[4]
        default: body = x[0] + x[1] + x[2] + x[3] + x[4] + "0000" + x[5]
        }
        return ns + body + check
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

        let items = Self.nutrients(from: v)

        guard items.contains(where: { $0.nutrientId == 1008 }) else { return nil }

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

    /// Open Food Facts' per-100 g values as USDA nutrients. Every `_100g` value there is in grams (vitamin A 6e-05 =
    /// 60 mcg), so mg nutrients are ×1,000 and mcg ones ×1,000,000; energy falls back from kJ.
    nonisolated static func nutrients(from v: (String) -> Double?) -> [FoodNutrientItem] {
        var items: [FoodNutrientItem] = []
        func add(_ id: Int, _ keys: [String], scale: Double = 1) {
            for key in keys { if let value = v(key) { items.append(FoodNutrientItem(nutrientId: id, value: value * scale)); return } }
        }
        let mg = 1_000.0, mcg = 1_000_000.0
        if let kcal = v("energy-kcal_100g") ?? v("energy_100g").map({ $0 / 4.184 }) {
            items.append(FoodNutrientItem(nutrientId: 1008, value: kcal))
        }
        add(1003, ["proteins_100g"])
        add(1005, ["carbohydrates_100g"])
        add(1004, ["fat_100g"])
        add(1079, ["fiber_100g"])
        add(2000, ["sugars_100g"])
        add(1258, ["saturated-fat_100g"])
        add(1253, ["cholesterol_100g"], scale: mg)
        if let sodium = v("sodium_100g") ?? v("salt_100g").map({ $0 / 2.5 }) {
            items.append(FoodNutrientItem(nutrientId: 1093, value: sodium * mg))
        }
        // Vitamins
        add(1106, ["vitamin-a_100g"], scale: mcg)
        add(1162, ["vitamin-c_100g"], scale: mg)
        add(1114, ["vitamin-d_100g"], scale: mcg)
        add(1109, ["vitamin-e_100g"], scale: mg)
        add(1185, ["vitamin-k_100g"], scale: mcg)
        add(1165, ["vitamin-b1_100g"], scale: mg)
        add(1166, ["vitamin-b2_100g"], scale: mg)
        add(1167, ["vitamin-pp_100g", "vitamin-b3_100g"], scale: mg)
        add(1175, ["vitamin-b6_100g"], scale: mg)
        add(1177, ["vitamin-b9_100g", "folates_100g"], scale: mcg)
        add(1178, ["vitamin-b12_100g"], scale: mcg)
        add(1180, ["choline_100g"], scale: mg)
        // Minerals
        add(1087, ["calcium_100g"], scale: mg)
        add(1089, ["iron_100g"], scale: mg)
        add(1090, ["magnesium_100g"], scale: mg)
        add(1091, ["phosphorus_100g"], scale: mg)
        add(1092, ["potassium_100g"], scale: mg)
        add(1095, ["zinc_100g"], scale: mg)
        add(1103, ["selenium_100g"], scale: mcg)
        add(1098, ["copper_100g"], scale: mg)
        add(1101, ["manganese_100g"], scale: mg)
        add(1100, ["iodine_100g"], scale: mcg)
        // Omega-3 for the Raw card: ALA, EPA, DHA.
        add(1404, ["alpha-linolenic-acid_100g"])
        add(1278, ["eicosapentaenoic-acid_100g"])
        add(1272, ["docosahexaenoic-acid_100g"])
        return items
    }
}
