import Foundation

/// Water that food contributes to hydration. About a fifth of most people's daily water comes from food, so the
/// Hydration total counts it alongside drinks.
enum FoodWater {
    /// Grams (≈ ml) of water in a logged portion.
    ///
    /// Uses the USDA figure when the entry has one. Otherwise it's estimated the way food composition tables
    /// derive it: portion weight minus protein, fat, carbohydrate, fibre and ash (~1% of weight). That works for
    /// meat, dairy, eggs, fruit and drinks alike, and dry foods like jerky or nuts correctly come out low.
    static func grams(in meal: MealEntry) -> Double {
        let mass = meal.servingSize
        guard mass > 0 else { return 0 }
        if meal.water > 0 { return min(meal.water, mass) }

        let solids = meal.protein + meal.totalFat + meal.carbohydrates + meal.fiber
        if solids == 0 {
            // No breakdown at all: zero-calorie items (coffee, tea, sparkling water) are nearly all water;
            // anything with calories but no macros gets a typical whole-food share.
            return meal.calories < 5 ? mass * 0.99 : mass * 0.6
        }
        let ash = mass * 0.01
        return max(0, min(mass * 0.99, mass - solids - ash))
    }

    /// Total for a set of meals, in millilitres.
    static func millilitres(in meals: [MealEntry]) -> Double {
        meals.reduce(0) { $0 + grams(in: $1) }
    }
}
