import Foundation

// MARK: - Recommended Daily Allowances (based on NIH/DRI tables)

struct NutrientGoals {
    // Macros
    let calories: Double
    let protein: Double       // g
    let carbohydrates: Double // g
    let fat: Double           // g
    let fiber: Double         // g
    let sodium: Double        // mg (max)

    // Vitamins
    let vitaminA: Double   // mcg RAE
    let vitaminC: Double   // mg
    let vitaminD: Double   // mcg
    let vitaminE: Double   // mg
    let vitaminK: Double   // mcg
    let thiamin: Double    // mg
    let riboflavin: Double // mg
    let niacin: Double     // mg
    let vitaminB6: Double  // mg
    let folate: Double     // mcg DFE
    let vitaminB12: Double // mcg

    // Minerals
    let calcium: Double    // mg
    let iron: Double       // mg
    let magnesium: Double  // mg
    let phosphorus: Double // mg
    let potassium: Double  // mg
    let zinc: Double       // mg
    let selenium: Double   // mcg
    let copper: Double     // mg
    let manganese: Double  // mg

    // MARK: - Build goals from user profile
    static func from(_ profile: UserProfile) -> NutrientGoals {
        let male = profile.sex == "male"
        let age  = profile.age
        let cal  = profile.dailyCalorieGoal

        return NutrientGoals(
            calories:      cal,
            protein:       cal * 0.15 / 4,
            carbohydrates: cal * 0.50 / 4,
            fat:           cal * 0.30 / 9,
            fiber:         male ? 38 : 25,
            sodium:        2300,
            vitaminA:      male ? 900 : 700,
            vitaminC:      male ? 90 : 75,
            vitaminD:      age >= 70 ? 20 : 15,
            vitaminE:      15,
            vitaminK:      male ? 120 : 90,
            thiamin:       male ? 1.2 : 1.1,
            riboflavin:    male ? 1.3 : 1.1,
            niacin:        male ? 16 : 14,
            vitaminB6:     age >= 51 ? (male ? 1.7 : 1.5) : 1.3,
            folate:        400,
            vitaminB12:    2.4,
            calcium:       age >= 51 ? 1200 : 1000,
            iron:          male ? 8 : (age >= 51 ? 8 : 18),
            magnesium:     male ? (age >= 31 ? 420 : 400) : (age >= 31 ? 320 : 310),
            phosphorus:    700,
            potassium:     male ? 3400 : 2600,
            zinc:          male ? 11 : 8,
            selenium:      55,
            copper:        0.9,
            manganese:     male ? 2.3 : 1.8
        )
    }

    static let `default` = NutrientGoals(
        calories: 2000, protein: 50, carbohydrates: 275, fat: 78,
        fiber: 28, sodium: 2300,
        vitaminA: 900, vitaminC: 90, vitaminD: 20, vitaminE: 15,
        vitaminK: 120, thiamin: 1.2, riboflavin: 1.3, niacin: 16,
        vitaminB6: 1.7, folate: 400, vitaminB12: 2.4,
        calcium: 1000, iron: 18, magnesium: 400, phosphorus: 700,
        potassium: 3500, zinc: 11, selenium: 55, copper: 0.9, manganese: 2.3
    )
}

// MARK: - A named, trackable nutrient for UI display
struct NutrientInfo: Identifiable {
    let id: String
    let name: String
    let unit: String
    let icon: String   // SF Symbol
    let group: NutrientGroup
    let current: Double
    let goal: Double

    var progress: Double { goal > 0 ? min(current / goal, 1.0) : 0 }
    var percentage: Int  { Int(progress * 100) }
    var isDeficient: Bool { progress < 0.5 }
    var isMet: Bool       { progress >= 0.9 }
}

enum NutrientGroup: String, CaseIterable {
    case macros    = "MACROS"
    case vitamins  = "VITAMINS"
    case minerals  = "MINERALS"
}

// MARK: - Build display list from daily totals + goals
func buildNutrientList(from meals: [MealEntry], goals: NutrientGoals) -> [NutrientInfo] {
    [
        // Macros
        NutrientInfo(id: "cal",  name: "Calories",  unit: "kcal", icon: "flame.fill",           group: .macros,   current: meals.totalCalories,   goal: goals.calories),
        NutrientInfo(id: "pro",  name: "Protein",   unit: "g",    icon: "bolt.fill",             group: .macros,   current: meals.totalProtein,    goal: goals.protein),
        NutrientInfo(id: "carb", name: "Carbs",     unit: "g",    icon: "leaf.fill",             group: .macros,   current: meals.totalCarbs,      goal: goals.carbohydrates),
        NutrientInfo(id: "fat",  name: "Fat",       unit: "g",    icon: "drop.fill",             group: .macros,   current: meals.totalFat,        goal: goals.fat),
        NutrientInfo(id: "fib",  name: "Fiber",     unit: "g",    icon: "circle.grid.cross.fill",group: .macros,   current: meals.totalFiber,      goal: goals.fiber),
        // Vitamins
        NutrientInfo(id: "va",   name: "Vitamin A", unit: "mcg",  icon: "eye.fill",              group: .vitamins, current: meals.totalVitaminA,   goal: goals.vitaminA),
        NutrientInfo(id: "vc",   name: "Vitamin C", unit: "mg",   icon: "shield.fill",           group: .vitamins, current: meals.totalVitaminC,   goal: goals.vitaminC),
        NutrientInfo(id: "vd",   name: "Vitamin D", unit: "mcg",  icon: "sun.max.fill",          group: .vitamins, current: meals.totalVitaminD,   goal: goals.vitaminD),
        NutrientInfo(id: "ve",   name: "Vitamin E", unit: "mg",   icon: "allergens.fill",        group: .vitamins, current: meals.totalVitaminE,   goal: goals.vitaminE),
        NutrientInfo(id: "vk",   name: "Vitamin K", unit: "mcg",  icon: "staroflife.fill",       group: .vitamins, current: meals.totalVitaminK,   goal: goals.vitaminK),
        NutrientInfo(id: "b1",   name: "Thiamin",   unit: "mg",   icon: "brain.fill",            group: .vitamins, current: meals.totalThiamin,    goal: goals.thiamin),
        NutrientInfo(id: "b2",   name: "Riboflavin",unit: "mg",   icon: "brain.fill",            group: .vitamins, current: meals.totalRiboflavin, goal: goals.riboflavin),
        NutrientInfo(id: "b3",   name: "Niacin",    unit: "mg",   icon: "brain.fill",            group: .vitamins, current: meals.totalNiacin,     goal: goals.niacin),
        NutrientInfo(id: "b6",   name: "Vitamin B6",unit: "mg",   icon: "brain.fill",            group: .vitamins, current: meals.totalVitaminB6,  goal: goals.vitaminB6),
        NutrientInfo(id: "fol",  name: "Folate",    unit: "mcg",  icon: "dna",                   group: .vitamins, current: meals.totalFolate,     goal: goals.folate),
        NutrientInfo(id: "b12",  name: "Vitamin B12",unit:"mcg",  icon: "brain.fill",            group: .vitamins, current: meals.totalVitaminB12, goal: goals.vitaminB12),
        // Minerals
        NutrientInfo(id: "ca",   name: "Calcium",   unit: "mg",   icon: "bolt.heart.fill",       group: .minerals, current: meals.totalCalcium,    goal: goals.calcium),
        NutrientInfo(id: "fe",   name: "Iron",      unit: "mg",   icon: "drop.fill",             group: .minerals, current: meals.totalIron,       goal: goals.iron),
        NutrientInfo(id: "mg",   name: "Magnesium", unit: "mg",   icon: "waveform.path.ecg",     group: .minerals, current: meals.totalMagnesium,  goal: goals.magnesium),
        NutrientInfo(id: "ph",   name: "Phosphorus",unit: "mg",   icon: "atom",                  group: .minerals, current: meals.totalPhosphorus, goal: goals.phosphorus),
        NutrientInfo(id: "k",    name: "Potassium", unit: "mg",   icon: "heart.fill",            group: .minerals, current: meals.totalPotassium,  goal: goals.potassium),
        NutrientInfo(id: "zn",   name: "Zinc",      unit: "mg",   icon: "shield.lefthalf.filled",group: .minerals, current: meals.totalZinc,       goal: goals.zinc),
        NutrientInfo(id: "se",   name: "Selenium",  unit: "mcg",  icon: "sparkles",              group: .minerals, current: meals.totalSelenium,   goal: goals.selenium),
        NutrientInfo(id: "cu",   name: "Copper",    unit: "mg",   icon: "circle.fill",           group: .minerals, current: meals.totalCopper,     goal: goals.copper),
        NutrientInfo(id: "mn",   name: "Manganese", unit: "mg",   icon: "circle.fill",           group: .minerals, current: meals.totalManganese,  goal: goals.manganese),
    ]
}

// MARK: - Nutrition score (0-1) used for character mood
func nutrientScore(meals: [MealEntry], goals: NutrientGoals) -> Double {
    guard !meals.isEmpty else { return 0 }
    let scores: [Double] = [
        min(meals.totalCalories   / goals.calories,   1.0),
        min(meals.totalProtein    / goals.protein,    1.0),
        min(meals.totalVitaminC   / goals.vitaminC,   1.0),
        min(meals.totalVitaminD   / goals.vitaminD,   1.0),
        min(meals.totalCalcium    / goals.calcium,    1.0),
        min(meals.totalIron       / goals.iron,       1.0),
        min(meals.totalMagnesium  / goals.magnesium,  1.0),
        min(meals.totalZinc       / goals.zinc,       1.0),
    ]
    return scores.reduce(0, +) / Double(scores.count)
}
