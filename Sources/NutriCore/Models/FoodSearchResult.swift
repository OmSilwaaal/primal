import Foundation

// MARK: - USDA FoodData Central API Models

struct USDASearchResponse: Codable {
    let totalHits: Int?
    let foods: [FoodSearchResult]
}

struct FoodSearchResult: Codable, Identifiable {
    let fdcId: Int
    let description: String
    let dataType: String?
    let brandOwner: String?
    let servingSize: Double?
    let servingSizeUnit: String?
    let foodNutrients: [FoodNutrientItem]

    var id: Int { fdcId }

    /// Returns the nutrient value (per 100g) for a given USDA nutrient ID.
    func nutrient(_ nutrientId: Int) -> Double {
        foodNutrients.first(where: { $0.nutrientId == nutrientId })?.value ?? 0
    }

    var caloriesPer100g: Double { nutrient(1008) }
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
}

struct FoodNutrientItem: Codable {
    let nutrientId: Int
    let nutrientName: String?
    let unitName: String?
    let value: Double

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
