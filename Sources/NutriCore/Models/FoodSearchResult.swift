import Foundation

// MARK: - USDA FoodData Central API Models

struct USDASearchResponse: Decodable {
    let totalHits: Int?
    let foods: [FoodSearchResult]
}

struct FoodSearchResult: Decodable, Identifiable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let brandOwner: String?
    let gtinUpc: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let foodNutrients: [FoodNutrientItem]

    var id: Int { fdcId }

    init(fdcId: Int, description: String, dataType: String? = nil, brandOwner: String? = nil,
         gtinUpc: String? = nil, servingSize: Double? = nil, servingSizeUnit: String? = nil,
         foodNutrients: [FoodNutrientItem]) {
        self.fdcId = fdcId
        self.description = description
        self.dataType = dataType
        self.brandOwner = brandOwner
        self.gtinUpc = gtinUpc
        self.servingSize = servingSize
        self.servingSizeUnit = servingSizeUnit
        self.foodNutrients = foodNutrients
    }

    private enum CodingKeys: String, CodingKey {
        case fdcId, description, dataType, brandOwner, gtinUpc, servingSize, servingSizeUnit, foodNutrients
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fdcId = try c.decode(Int.self, forKey: .fdcId)
        description = (try? c.decode(String.self, forKey: .description)) ?? "Unknown food"
        dataType = try? c.decode(String.self, forKey: .dataType)
        brandOwner = try? c.decode(String.self, forKey: .brandOwner)
        gtinUpc = try? c.decode(String.self, forKey: .gtinUpc)
        servingSize = try? c.decode(Double.self, forKey: .servingSize)
        servingSizeUnit = try? c.decode(String.self, forKey: .servingSizeUnit)
        foodNutrients = (try? c.decode([FoodNutrientItem].self, forKey: .foodNutrients)) ?? []
    }

    /// Returns the nutrient value (per 100g) for a given USDA nutrient ID.
    func nutrient(_ nutrientId: Int) -> Double {
        foodNutrients.first(where: { $0.nutrientId == nutrientId })?.value ?? 0
    }

    /// The first of `ids` the food actually lists (0 when none). USDA's datasets disagree on IDs: Foundation foods —
    /// including the raw beef cuts — have no 1008 Energy and give it as 2047/2048 (Atwater) instead.
    func nutrient(firstOf ids: [Int]) -> Double {
        for id in ids {
            if let v = foodNutrients.first(where: { $0.nutrientId == id })?.value { return v }
        }
        return 0
    }

    /// kcal per 100 g: Energy (1008), else Atwater general (2047), else Atwater specific (2048), else worked out
    /// from the macros (4 / 4 / 9 kcal per g) — a few USDA records (e.g. "Butter, stick, salted") list none at all.
    var energyKcal: Double {
        let listed = nutrient(firstOf: [1008, 2047, 2048])
        if listed > 0 { return listed }
        return 4 * nutrient(1003) + 4 * nutrient(1005) + 9 * nutrient(1004)
    }

    /// How many nutrients the record carries: SR Legacy foods list ~100, newer Foundation ones often ~20.
    var nutrientCount: Int { foodNutrients.filter { $0.value > 0 }.count }

    var caloriesPer100g: Double { energyKcal }
    var proteinPer100g: Double  { nutrient(1003) }
    var carbsPer100g: Double    { nutrient(1005) }
    var fatPer100g: Double      { nutrient(1004) }

    var displayName: String {
        description
            .split(separator: ",")
            .first
            .map(String.init) ?? description
    }

    var subtitle: String {
        let parts = [brandOwner, dataType].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    /// Sensible starting portion: the label serving for branded foods, otherwise 100 g.
    var defaultServingGrams: Double {
        // USDA Branded writes grams as "g" or "GRM"; Open Food Facts as "g".
        if let size = servingSize, size > 0, ["g", "grm", "gram", "grams"].contains(servingSizeUnit?.lowercased() ?? "") {
            return size.rounded()
        }
        return 100
    }
}

struct FoodNutrientItem: Codable {
    let nutrientId: Int
    let nutrientName: String?
    let unitName: String?
    let value: Double

    init(nutrientId: Int, value: Double, nutrientName: String? = nil, unitName: String? = nil) {
        self.nutrientId = nutrientId
        self.value = value
        self.nutrientName = nutrientName
        self.unitName = unitName
    }

    private enum CodingKeys: String, CodingKey {
        case nutrientId, nutrientName, unitName, value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nutrientId  = try c.decode(Int.self, forKey: .nutrientId)
        nutrientName = try? c.decode(String.self, forKey: .nutrientName)
        unitName    = try? c.decode(String.self, forKey: .unitName)
        value       = (try? c.decode(Double.self, forKey: .value)) ?? 0
    }
}

// MARK: - Key USDA Nutrient IDs (reference)
/*
 1008  Energy (kcal)
 1003  Protein (g)
 1004  Total Fat (g)
 1005  Carbohydrates (g)
 1079  Fiber (g)
 2000  Total Sugars (g)
 1258  Saturated Fat (g)
 1253  Cholesterol (mg)
 1093  Sodium (mg)
 1106  Vitamin A (mcg RAE)
 1162  Vitamin C (mg)
 1114  Vitamin D (mcg)
 1109  Vitamin E (mg)
 1185  Vitamin K (mcg)
 1165  Thiamin B1 (mg)
 1166  Riboflavin B2 (mg)
 1167  Niacin B3 (mg)
 1175  Vitamin B6 (mg)
 1177  Folate (mcg DFE)
 1178  Vitamin B12 (mcg)
 1087  Calcium (mg)
 1089  Iron (mg)
 1090  Magnesium (mg)
 1091  Phosphorus (mg)
 1092  Potassium (mg)
 1095  Zinc (mg)
 1103  Selenium (mcg)
 1098  Copper (mg)
 1101  Manganese (mg)
*/
