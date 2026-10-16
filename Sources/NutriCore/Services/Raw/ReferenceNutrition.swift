import Foundation

/// Offline fallback nutrition per 100 g of raw food, used when USDA FoodData Central is unreachable.
/// Values are rounded approximations of USDA reference entries, flagged as "Reference estimate" in the app.
struct RefNutrients {
    var kcal = 0.0, protein = 0.0, fat = 0.0, carbs = 0.0
    var cholesterol = 0.0, sodium = 0.0, potassium = 0.0, magnesium = 0.0, calcium = 0.0
    var iron = 0.0, zinc = 0.0, selenium = 0.0, copper = 0.0, phosphorus = 0.0
    var vitaminA = 0.0, vitaminC = 0.0, vitaminD = 0.0, vitaminE = 0.0, vitaminK2 = 0.0
    var b12 = 0.0, folate = 0.0, choline = 0.0, iodine = 0.0
    var omega3 = 0.0, omega6 = 0.0, purines = 0.0
}

enum ReferenceNutrition {
    static func lookup(species: RawSpecies, category: CutCategory, organ: String, ground: Bool) -> RefNutrients {
        if category == .fat {
            return organ == FatType.suet.rawValue
                ? RefNutrients(kcal: 854, fat: 94, cholesterol: 109, vitaminE: 2.7, omega6: 1.5, purines: 0)
                : RefNutrients(kcal: 902, fat: 100, cholesterol: 109, vitaminE: 2.7, omega6: 3.1, purines: 0)
        }
        if category == .organ { return organReference(species: species, organ: Organ(rawValue: organ) ?? .liver) }
        return muscle(species: species, ground: ground)
    }

    private static func organReference(species: RawSpecies, organ: Organ) -> RefNutrients {
        switch organ {
        case .liver:
            return RefNutrients(kcal: 135, protein: 20.4, fat: 3.6, carbs: 3.9, cholesterol: 275, sodium: 69, potassium: 313,
                                magnesium: 18, calcium: 5, iron: 4.9, zinc: 4, selenium: 39.7, copper: 9.8, phosphorus: 387,
                                vitaminA: species == .poultry ? 3300 : 4970, vitaminC: 1.3, vitaminD: 1.2, vitaminE: 0.4,
                                vitaminK2: 3, b12: 59, folate: 253, choline: 333, iodine: 3, omega3: 0.1, omega6: 0.4, purines: 300)
        case .heart:
            return RefNutrients(kcal: 112, protein: 17.7, fat: 3.9, carbs: 0.1, cholesterol: 150, sodium: 98, potassium: 287,
                                magnesium: 21, calcium: 5, iron: 4.3, zinc: 1.7, selenium: 21.8, copper: 0.4, phosphorus: 212,
                                vitaminA: 0, vitaminC: 3.7, vitaminE: 0.3, b12: 8.6, folate: 2, choline: 193, iodine: 3, omega3: 0.1, omega6: 0.4, purines: 120)
        case .kidney:
            return RefNutrients(kcal: 99, protein: 17.4, fat: 3.1, carbs: 0, cholesterol: 411, sodium: 182, potassium: 262,
                                magnesium: 17, calcium: 13, iron: 4.6, zinc: 1.9, selenium: 141, copper: 0.4, phosphorus: 257,
                                vitaminA: 33, vitaminC: 9.4, vitaminD: 0.6, b12: 27.5, folate: 98, choline: 270, iodine: 4, omega3: 0.1, omega6: 0.3, purines: 200)
        case .spleen:
            return RefNutrients(kcal: 105, protein: 18, fat: 3, carbs: 0, cholesterol: 250, sodium: 87, potassium: 380,
                                magnesium: 18, calcium: 10, iron: 41, zinc: 2, selenium: 30, copper: 0.1, phosphorus: 280,
                                vitaminC: 15, b12: 8, folate: 20, choline: 150, purines: 270)
        case .brain:
            return RefNutrients(kcal: 143, protein: 10.5, fat: 10.3, carbs: 0, cholesterol: 1352, sodium: 126, potassium: 288,
                                magnesium: 13, calcium: 10, iron: 2.4, zinc: 1, selenium: 21, copper: 0.3, phosphorus: 311,
                                vitaminC: 15, vitaminD: 1, b12: 10, folate: 4, choline: 400, omega3: 0.4, omega6: 0.2, purines: 175)
        case .marrow:
            return RefNutrients(kcal: 786, protein: 6.7, fat: 84, carbs: 0, cholesterol: 120, sodium: 35, iron: 1.3, zinc: 1,
                                vitaminE: 2, omega6: 1.5, purines: 20)
        }
    }

    private static func muscle(species: RawSpecies, ground: Bool) -> RefNutrients {
        switch species {
        case .beef:
            return ground
                ? RefNutrients(kcal: 254, protein: 17.2, fat: 20, cholesterol: 71, sodium: 66, potassium: 270, magnesium: 17, calcium: 12,
                               iron: 1.9, zinc: 4.4, selenium: 15, copper: 0.07, phosphorus: 158, vitaminA: 0, vitaminD: 0.1,
                               vitaminE: 0.2, vitaminK2: 3, b12: 2.1, folate: 6, choline: 70, iodine: 3, omega3: 0.05, omega6: 0.4, purines: 120)
                : RefNutrients(kcal: 291, protein: 18, fat: 24, cholesterol: 69, sodium: 55, potassium: 300, magnesium: 18, calcium: 8,
                               iron: 1.8, zinc: 4.5, selenium: 18, copper: 0.07, phosphorus: 175, vitaminD: 0.1, vitaminE: 0.3,
                               vitaminK2: 3, b12: 2, folate: 6, choline: 70, iodine: 3, omega3: 0.06, omega6: 0.5, purines: 120)
        case .lamb:
            return RefNutrients(kcal: 282, protein: 16.6, fat: 23.4, cholesterol: 73, sodium: 59, potassium: 222, magnesium: 20, calcium: 16,
                                iron: 1.6, zinc: 3.4, selenium: 18, copper: 0.1, phosphorus: 147, vitaminD: 0.1, vitaminK2: 3, b12: 2.3,
                                folate: 18, choline: 67, iodine: 3, omega3: 0.4, omega6: 0.8, purines: 130)
        case .bison:
            return RefNutrients(kcal: 146, protein: 20, fat: 7.2, cholesterol: 62, sodium: 56, potassium: 330, magnesium: 22, calcium: 12,
                                iron: 3.4, zinc: 4.4, selenium: 22, copper: 0.1, phosphorus: 190, vitaminE: 0.3, vitaminK2: 3, b12: 2.7,
                                folate: 8, choline: 80, iodine: 3, omega3: 0.1, omega6: 0.3, purines: 120)
        case .pork:
            return ground
                ? RefNutrients(kcal: 263, protein: 16.9, fat: 21.2, cholesterol: 72, sodium: 56, potassium: 287, magnesium: 16, calcium: 14,
                               iron: 0.9, zinc: 2.4, selenium: 23, copper: 0.06, phosphorus: 164, vitaminD: 0.9, vitaminK2: 5, b12: 0.7,
                               folate: 3, choline: 60, iodine: 3, omega3: 0.1, omega6: 2.4, purines: 130)
                : RefNutrients(kcal: 143, protein: 21, fat: 6, cholesterol: 59, sodium: 51, potassium: 423, magnesium: 24, calcium: 5,
                               iron: 0.8, zinc: 2.0, selenium: 36, copper: 0.07, phosphorus: 247, vitaminD: 1.0, vitaminK2: 5, b12: 0.7,
                               folate: 5, choline: 75, iodine: 3, omega3: 0.06, omega6: 0.9, purines: 130)
        case .poultry:
            return RefNutrients(kcal: 209, protein: 17, fat: 15, cholesterol: 97, sodium: 84, potassium: 220, magnesium: 20, calcium: 12,
                                iron: 0.9, zinc: 1.9, selenium: 18, copper: 0.07, phosphorus: 150, vitaminA: 50, vitaminD: 0.1,
                                vitaminE: 0.3, vitaminK2: 10, b12: 0.3, folate: 6, choline: 70, iodine: 3, omega3: 0.1, omega6: 3.0, purines: 150)
        case .fish:
            return RefNutrients(kcal: 208, protein: 20, fat: 13, cholesterol: 55, sodium: 59, potassium: 363, magnesium: 27, calcium: 9,
                                iron: 0.3, zinc: 0.4, selenium: 36, copper: 0.05, phosphorus: 240, vitaminA: 12, vitaminD: 11,
                                vitaminE: 3.5, vitaminK2: 1, b12: 3.2, folate: 26, choline: 90, iodine: 35, omega3: 2.0, omega6: 0.6, purines: 170)
        case .shellfish:
            return RefNutrients(kcal: 51, protein: 5.7, fat: 1.5, carbs: 2.7, cholesterol: 25, sodium: 106, potassium: 168, magnesium: 22, calcium: 45,
                                iron: 5.1, zinc: 16.6, selenium: 77, copper: 4.5, phosphorus: 97, vitaminA: 16, vitaminC: 4, vitaminD: 8,
                                vitaminE: 0.9, b12: 16, folate: 10, choline: 65, iodine: 60, omega3: 0.4, omega6: 0.04, purines: 130)
        case .deer:
            return RefNutrients(kcal: 120, protein: 23, fat: 2.4, cholesterol: 85, sodium: 51, potassium: 318, magnesium: 22, calcium: 5,
                                iron: 3.4, zinc: 2.9, selenium: 9, copper: 0.3, phosphorus: 200, vitaminK2: 3, b12: 6.3, folate: 4,
                                choline: 90, iodine: 3, omega3: 0.1, omega6: 0.3, purines: 130)
        case .elk:
            return RefNutrients(kcal: 111, protein: 22.9, fat: 1.5, cholesterol: 55, sodium: 52, potassium: 330, magnesium: 25, calcium: 5,
                                iron: 3.1, zinc: 2.8, selenium: 9, copper: 0.3, phosphorus: 200, vitaminK2: 3, b12: 6, folate: 4,
                                choline: 90, iodine: 3, omega3: 0.1, omega6: 0.3, purines: 130)
        case .bear:
            return RefNutrients(kcal: 161, protein: 20, fat: 8.5, cholesterol: 80, sodium: 60, potassium: 330, magnesium: 22, calcium: 12,
                                iron: 5, zinc: 4, selenium: 15, copper: 0.2, phosphorus: 190, b12: 4, folate: 5, choline: 90, omega3: 0.2, omega6: 0.9, purines: 130)
        case .rabbit:
            return RefNutrients(kcal: 136, protein: 20.1, fat: 5.5, cholesterol: 57, sodium: 41, potassium: 330, magnesium: 18, calcium: 13,
                                iron: 2.3, zinc: 1.6, selenium: 28, copper: 0.1, phosphorus: 220, b12: 7.2, folate: 8, choline: 115, omega3: 0.2, omega6: 0.9, purines: 130)
        case .otherGame:
            return RefNutrients(kcal: 130, protein: 21, fat: 4, cholesterol: 70, sodium: 55, potassium: 320, magnesium: 22, calcium: 8,
                                iron: 3, zinc: 3, selenium: 12, copper: 0.2, phosphorus: 200, b12: 4, folate: 5, choline: 90, omega3: 0.2, omega6: 0.5, purines: 130)
        }
    }

    /// Builds a MealEntry (nutrients scaled to `grams`) from reference data.
    static func entry(species: RawSpecies, category: CutCategory, organ: String, ground: Bool, grams: Double) -> MealEntry {
        let r = lookup(species: species, category: category, organ: organ, ground: ground)
        let f = grams / 100
        let e = MealEntry()
        e.servingSize = grams
        e.source = "Reference estimate"
        e.calories = r.kcal * f; e.protein = r.protein * f; e.totalFat = r.fat * f; e.carbohydrates = r.carbs * f
        e.cholesterol = r.cholesterol * f; e.sodium = r.sodium * f; e.potassium = r.potassium * f
        e.magnesium = r.magnesium * f; e.calcium = r.calcium * f; e.iron = r.iron * f; e.zinc = r.zinc * f
        e.selenium = r.selenium * f; e.copper = r.copper * f; e.phosphorus = r.phosphorus * f
        e.vitaminA = r.vitaminA * f; e.vitaminC = r.vitaminC * f; e.vitaminD = r.vitaminD * f
        e.vitaminE = r.vitaminE * f; e.vitaminK2 = r.vitaminK2 * f
        e.vitaminB12 = r.b12 * f; e.folate = r.folate * f; e.choline = r.choline * f; e.iodine = r.iodine * f
        e.omega3 = r.omega3 * f; e.omega6 = r.omega6 * f; e.purines = r.purines * f
        e.hemeIron = r.iron * f * 0.4
        return e
    }
}
