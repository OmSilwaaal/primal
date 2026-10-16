import Foundation
import SwiftData

// MARK: - Meal Entry (persisted per food item logged)
@Model
final class MealEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var foodName: String = ""
    var fdcId: Int = 0
    var servingSize: Double = 100.0  // grams
    var source: String = ""          // "USDA" | "Open Food Facts" | "AI estimate"

    // ── Macros ──────────────────────────────────────────────────────────────
    var calories: Double = 0
    var protein: Double = 0
    var carbohydrates: Double = 0
    var totalFat: Double = 0
    var fiber: Double = 0
    var sugar: Double = 0
    var saturatedFat: Double = 0
    var cholesterol: Double = 0
    var sodium: Double = 0

    // ── Vitamins ─────────────────────────────────────────────────────────────
    var vitaminA: Double = 0      // mcg RAE
    var vitaminC: Double = 0      // mg
    var vitaminD: Double = 0      // mcg
    var vitaminE: Double = 0      // mg
    var vitaminK: Double = 0      // mcg
    var thiamin: Double = 0       // mg (B1)
    var riboflavin: Double = 0    // mg (B2)
    var niacin: Double = 0        // mg (B3)
    var vitaminB6: Double = 0     // mg
    var folate: Double = 0        // mcg DFE
    var vitaminB12: Double = 0    // mcg

    // ── Minerals ─────────────────────────────────────────────────────────────
    var calcium: Double = 0       // mg
    var iron: Double = 0          // mg
    var magnesium: Double = 0     // mg
    var phosphorus: Double = 0    // mg
    var potassium: Double = 0     // mg
    var zinc: Double = 0          // mg
    var selenium: Double = 0      // mcg
    var copper: Double = 0        // mg
    var manganese: Double = 0     // mg

    // ── Carnivore-focused nutrients ──────────────────────────────────────────
    var choline: Double = 0       // mg
    var iodine: Double = 0        // mcg
    var vitaminK2: Double = 0     // mcg
    var hemeIron: Double = 0      // mg (estimated share of iron)
    var omega3: Double = 0        // g
    var omega6: Double = 0        // g
    var purines: Double = 0       // mg (estimated)

    // ── Raw / carnivore tagging ──────────────────────────────────────────────
    var species: String = ""      // RawSpecies.rawValue, empty for non-tagged foods
    var cutCategory: String = ""  // CutCategory.rawValue
    var organType: String = ""    // Organ / FatType rawValue
    var prep: String = ""         // Prep.rawValue
    var isGround: Bool = false
    var rearing: String = ""      // Rearing.rawValue
    var supplierName: String = ""
    var batchId: UUID? = nil
    var thawMethod: String = ""
    var outOfFridgeMin: Double = 0
    var riskScore: Double = 0     // 0…100 pathogen risk at log time
    var costUSD: Double = 0
    @Attribute(.externalStorage) var photoData: Data? = nil

    init() {}

    /// Entry from an AI estimate. Macros are for the whole estimated serving and are scaled to `servingSize`.
    init(from ai: AIFoodResult, servingSize: Double) {
        let base = ai.servingSize > 0 ? ai.servingSize : 100
        let f = servingSize / base
        self.foodName = ai.name
        self.source = "AI estimate"
        self.servingSize = servingSize
        calories = ai.calories * f
        protein = ai.protein * f
        carbohydrates = ai.carbohydrates * f
        totalFat = ai.totalFat * f
    }

    // Convenience init from USDA search result
    init(from result: FoodSearchResult, servingSize: Double) {
        self.foodName = result.description.isEmpty ? "Food" : result.description
        self.fdcId = result.fdcId
        self.source = result.dataType == "Open Food Facts" ? "Open Food Facts" : "USDA"
        self.servingSize = servingSize
        let f = servingSize / 100.0  // scale factor (USDA values are per 100g)

        calories = result.nutrient(1008) * f
        protein = result.nutrient(1003) * f
        carbohydrates = result.nutrient(1005) * f
        totalFat = result.nutrient(1004) * f
        fiber = result.nutrient(1079) * f
        sugar = (result.nutrient(2000) > 0 ? result.nutrient(2000) : result.nutrient(1063)) * f
        saturatedFat = result.nutrient(1258) * f
        cholesterol = result.nutrient(1253) * f
        sodium = result.nutrient(1093) * f

        vitaminA = result.nutrient(1106) * f
        vitaminC = result.nutrient(1162) * f
        vitaminD = result.nutrient(1114) * f
        vitaminE = result.nutrient(1109) * f
        vitaminK = result.nutrient(1185) * f
        thiamin = result.nutrient(1165) * f
        riboflavin = result.nutrient(1166) * f
        niacin = result.nutrient(1167) * f
        vitaminB6 = result.nutrient(1175) * f
        folate = result.nutrient(1177) * f
        vitaminB12 = result.nutrient(1178) * f

        calcium = result.nutrient(1087) * f
        iron = result.nutrient(1089) * f
        magnesium = result.nutrient(1090) * f
        phosphorus = result.nutrient(1091) * f
        potassium = result.nutrient(1092) * f
        zinc = result.nutrient(1095) * f
        selenium = result.nutrient(1103) * f
        copper = result.nutrient(1098) * f
        manganese = result.nutrient(1101) * f

        choline = result.nutrient(1180) * f
        iodine = result.nutrient(1100) * f
        vitaminK2 = result.nutrient(1183) * f
        omega3 = (result.nutrient(1404) + result.nutrient(1278) + result.nutrient(1272) + result.nutrient(1280)) * f
        omega6 = (result.nutrient(1316) + result.nutrient(1313)) * f
    }
}

// MARK: - Aggregate helpers (sum across an array of entries)
extension Array where Element == MealEntry {
    var totalCalories: Double    { reduce(0) { $0 + $1.calories } }
    var totalProtein: Double     { reduce(0) { $0 + $1.protein } }
    var totalCarbs: Double       { reduce(0) { $0 + $1.carbohydrates } }
    var totalFat: Double         { reduce(0) { $0 + $1.totalFat } }
    var totalFiber: Double       { reduce(0) { $0 + $1.fiber } }
    var totalSodium: Double      { reduce(0) { $0 + $1.sodium } }
    var totalVitaminA: Double    { reduce(0) { $0 + $1.vitaminA } }
    var totalVitaminC: Double    { reduce(0) { $0 + $1.vitaminC } }
    var totalVitaminD: Double    { reduce(0) { $0 + $1.vitaminD } }
    var totalVitaminE: Double    { reduce(0) { $0 + $1.vitaminE } }
    var totalVitaminK: Double    { reduce(0) { $0 + $1.vitaminK } }
    var totalThiamin: Double     { reduce(0) { $0 + $1.thiamin } }
    var totalRiboflavin: Double  { reduce(0) { $0 + $1.riboflavin } }
    var totalNiacin: Double      { reduce(0) { $0 + $1.niacin } }
    var totalVitaminB6: Double   { reduce(0) { $0 + $1.vitaminB6 } }
    var totalFolate: Double      { reduce(0) { $0 + $1.folate } }
    var totalVitaminB12: Double  { reduce(0) { $0 + $1.vitaminB12 } }
    var totalCalcium: Double     { reduce(0) { $0 + $1.calcium } }
    var totalIron: Double        { reduce(0) { $0 + $1.iron } }
    var totalMagnesium: Double   { reduce(0) { $0 + $1.magnesium } }
    var totalPhosphorus: Double  { reduce(0) { $0 + $1.phosphorus } }
    var totalPotassium: Double   { reduce(0) { $0 + $1.potassium } }
    var totalZinc: Double        { reduce(0) { $0 + $1.zinc } }
    var totalSelenium: Double    { reduce(0) { $0 + $1.selenium } }
    var totalCopper: Double      { reduce(0) { $0 + $1.copper } }
    var totalManganese: Double   { reduce(0) { $0 + $1.manganese } }
    var totalCholine: Double     { reduce(0) { $0 + $1.choline } }
    var totalIodine: Double      { reduce(0) { $0 + $1.iodine } }
    var totalVitaminK2: Double   { reduce(0) { $0 + $1.vitaminK2 } }
    var totalHemeIron: Double    { reduce(0) { $0 + $1.hemeIron } }
    var totalOmega3: Double      { reduce(0) { $0 + $1.omega3 } }
    var totalOmega6: Double      { reduce(0) { $0 + $1.omega6 } }
    var totalPurines: Double     { reduce(0) { $0 + $1.purines } }
    var totalCholesterol: Double { reduce(0) { $0 + $1.cholesterol } }
    var totalCost: Double        { reduce(0) { $0 + $1.costUSD } }
}
