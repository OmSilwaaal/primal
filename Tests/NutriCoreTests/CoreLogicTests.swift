import XCTest
@testable import NutriCore

/// The maths every screen depends on: targets, how a food becomes a logged meal, scores, on-target days, streaks.
final class CoreLogicTests: XCTestCase {

    // MARK: Helpers

    private func food(_ nutrients: [Int: Double], type: String = "SR Legacy") -> FoodSearchResult {
        FoodSearchResult(fdcId: 1, description: "Test food", dataType: type,
                         foodNutrients: nutrients.map { FoodNutrientItem(nutrientId: $0.key, value: $0.value) })
    }

    private func meal(kcal: Double, daysAgo: Int = 0) -> MealEntry {
        let m = MealEntry()
        m.calories = kcal
        m.date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return m
    }

    // MARK: Daily energy target

    func testTDEEMatchesMifflinStJeor() {
        // 10×70 + 6.25×170 − 5×25 + 5 = 1642.5, × 1.55 (moderate)
        XCTAssertEqual(UserProfile.tdee(male: true, weightKg: 70, heightCm: 170, age: 25, activity: "moderate"),
                       2545.875, accuracy: 0.001)
        // Female: −161 instead of +5; sedentary × 1.2
        XCTAssertEqual(UserProfile.tdee(male: false, weightKg: 60, heightCm: 165, age: 30, activity: "sedentary"),
                       (600 + 1031.25 - 150 - 161) * 1.2, accuracy: 0.001)
    }

    func testTDEENeverBelowFloor() {
        XCTAssertEqual(UserProfile.tdee(male: false, weightKg: 35, heightCm: 130, age: 90, activity: "sedentary"), 1200)
    }

    // MARK: Food → meal

    func testFoundationFoodsWithoutEnergyIDUseAtwater() {
        // USDA Foundation raw beef cuts list energy only as 2047 (Atwater general), never 1008.
        let steak = food([2047: 143, 2048: 149, 1003: 22], type: "Foundation")
        XCTAssertEqual(steak.energyKcal, 143)
        let entry = MealEntry(from: steak, servingSize: 200)
        XCTAssertEqual(entry.calories, 286, accuracy: 0.001)
        XCTAssertEqual(entry.protein, 44, accuracy: 0.001)
    }

    func testStandardEnergyIDWinsWhenPresent() {
        XCTAssertEqual(food([1008: 135, 2047: 999]).energyKcal, 135)
    }

    func testNutrientsScaleFromPer100g() {
        // SR Legacy beef liver, raw, per 100 g.
        let liver = food([1008: 135, 1178: 59.3, 1106: 4970, 1190: 290, 1089: 4.9])
        let entry = MealEntry(from: liver, servingSize: 50)
        XCTAssertEqual(entry.calories, 67.5, accuracy: 0.001)
        XCTAssertEqual(entry.vitaminB12, 29.65, accuracy: 0.001)
        XCTAssertEqual(entry.vitaminA, 2485, accuracy: 0.001)
        XCTAssertEqual(entry.folate, 145, accuracy: 0.001)
        XCTAssertEqual(entry.iron, 2.45, accuracy: 0.001)
    }

    func testFolatePrefersDFE() {
        XCTAssertEqual(MealEntry(from: food([1190: 300, 1177: 200]), servingSize: 100).folate, 300, accuracy: 0.001)
        XCTAssertEqual(MealEntry(from: food([1177: 200]), servingSize: 100).folate, 200, accuracy: 0.001)
    }

    func testUSDAResponseDecodesAndSurvivesMissingFields() throws {
        let json = """
        {"totalHits": 1, "foods": [{"fdcId": 169451, "description": "Beef, liver, raw", "dataType": "SR Legacy",
          "foodNutrients": [{"nutrientId": 1008, "nutrientName": "Energy", "unitName": "KCAL", "value": 135},
                            {"nutrientId": 1003, "value": 20.4}, {"nutrientId": 1178}]}]}
        """
        let response = try JSONDecoder().decode(USDASearchResponse.self, from: Data(json.utf8))
        let liver = try XCTUnwrap(response.foods.first)
        XCTAssertEqual(liver.caloriesPer100g, 135)
        XCTAssertEqual(liver.proteinPer100g, 20.4)
        XCTAssertEqual(liver.nutrient(1178), 0)   // listed without a value
        XCTAssertEqual(liver.defaultServingGrams, 100)
    }

    // MARK: Nutrient list and scores

    func testNutrientListCoversEveryGroup() {
        let list = buildNutrientList(from: [], goals: .default)
        XCTAssertEqual(list.count, 25)
        XCTAssertEqual(list.filter { $0.group == .macros }.count, 5)
        XCTAssertEqual(list.filter { $0.group == .vitamins }.count, 11)
        XCTAssertEqual(list.filter { $0.group == .minerals }.count, 9)
        XCTAssertEqual(Set(list.map(\.id)).count, 25, "ids must be unique")
    }

    func testProgressCapsAtOneAndStatusThresholds() {
        func info(_ current: Double) -> NutrientInfo {
            NutrientInfo(id: "x", name: "X", unit: "mg", icon: "", group: .minerals, current: current, goal: 10)
        }
        XCTAssertEqual(info(25).progress, 1)
        XCTAssertTrue(info(9).isMet)
        XCTAssertFalse(info(8.9).isMet)
        XCTAssertTrue(info(4.9).isDeficient)
        XCTAssertFalse(info(5).isDeficient)
        XCTAssertEqual(NutrientInfo(id: "x", name: "X", unit: "", icon: "", group: .macros, current: 5, goal: 0).progress, 0)
    }

    func testGroupScoreIsAverageCappedShare() {
        let items = [10.0, 5, 0, 40].map {
            NutrientInfo(id: "\($0)", name: "", unit: "", icon: "", group: .vitamins, current: $0, goal: 10)
        }
        // (1 + 0.5 + 0 + 1) / 4 = 62.5 → 63
        XCTAssertEqual(DataGroupSummary.score(items), 63)
        XCTAssertEqual(DataGroupSummary.score([]), 0)
    }

    func testSummariesAreMacrosVitaminsMineralsRawSeasonal() {
        let all = buildNutrientList(from: [], goals: .default) + buildRawList(from: [], isMale: true)
        let summaries = DataGroupSummary.make(from: all, season: "Fall")
        XCTAssertEqual(summaries.map(\.kind), [.macros, .vitamins, .minerals, .raw, .seasonal])
        XCTAssertEqual(summaries[3].items.map(\.id), ["raw", "org", "chol", "o3", "k2", "iod"])
        XCTAssertTrue(summaries[4].isSeasonal)
        XCTAssertEqual(summaries[4].seasonName, "Fall")
        XCTAssertEqual(Set(DataGroupKind.allCases.map(\.scene)).count, 5, "every card has its own scene")
    }

    // MARK: Seasonal

    func testEverySeasonHasFoodsAndHemispheresFlip() {
        for kind in [Season.Kind.spring, .summer, .autumn, .winter] {
            XCTAssertEqual(SeasonalGuide.foods(for: kind).count, 6)
        }
        let july = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        XCTAssertEqual(SeasonalGuide.foods(for: Season(date: july, latitude: -33).kind).first?.id, "shellfish")
    }

    func testSeasonalPicksMatchRecentLogsByWord() {
        let oysters = MealEntry(); oysters.foodName = "Mollusks, oyster, Pacific, raw"; oysters.date = .now
        let oldLiver = MealEntry(); oldLiver.foodName = "Beef, liver, raw"
        oldLiver.date = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        let eggplant = MealEntry(); eggplant.foodName = "Eggplant, raw"; eggplant.date = .now
        let autumn = Season(date: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1))!, latitude: 40)
        let picks = SeasonalGuide.picks(for: autumn, meals: [oysters, oldLiver, eggplant])
        XCTAssertTrue(picks.first { $0.id == "oysters" }!.eaten)
        XCTAssertFalse(picks.first { $0.id == "organs" }!.eaten, "older than 14 days")
        let spring = Season(date: Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 1))!, latitude: 40)
        XCTAssertFalse(SeasonalGuide.picks(for: spring, meals: [eggplant]).first { $0.id == "eggs" }!.eaten,
                       "eggplant is not eggs")
        let summaries = DataGroupSummary.make(from: [], season: "Fall", seasonal: picks)
        XCTAssertEqual(summaries.last?.seasonalEaten, 1)
        XCTAssertEqual(summaries.last?.score, 17)   // 1 of 6
    }

    // MARK: Raw card

    func testRawShareAndOrganMeat() {
        let liver = MealEntry(); liver.foodName = "Beef, variety meats and by-products, liver, raw"; liver.servingSize = 60
        let steak = MealEntry(); steak.foodName = "Beef, top sirloin steak, raw"; steak.servingSize = 200
        let eggs = MealEntry(); eggs.foodName = "Egg, whole, cooked, scrambled"; eggs.servingSize = 140
        let tagged = MealEntry(); tagged.foodName = "Heart slices"; tagged.prep = "raw"; tagged.servingSize = 40
        XCTAssertTrue(liver.isRawFood && liver.isOrganMeat)
        XCTAssertTrue(steak.isRawFood); XCTAssertFalse(steak.isOrganMeat)
        XCTAssertFalse(eggs.isRawFood); XCTAssertFalse(eggs.isOrganMeat)
        XCTAssertFalse({ let m = MealEntry(); m.foodName = "Strawberries"; return m.isRawFood }(), "\"raw\" must be a whole word")

        let list = buildRawList(from: [liver, steak, eggs, tagged], isMale: false)
        let raw = list.first { $0.id == "raw" }!, organ = list.first { $0.id == "org" }!
        XCTAssertEqual(raw.current, 300); XCTAssertEqual(raw.goal, 440)    // 60 + 200 + 40 of 440 g
        XCTAssertEqual(organ.current, 100); XCTAssertEqual(organ.goal, 50) // liver + heart
        XCTAssertEqual(list.first { $0.id == "chol" }!.goal, 425)          // women's adequate intake
    }

    // MARK: Days, streaks, averages

    func testDayGoalRange() {
        XCTAssertEqual(DayGoal(kcal: 0, goal: 2000), .none)
        XCTAssertEqual(DayGoal(kcal: 1700, goal: 2000), .onTarget)   // 85%
        XCTAssertEqual(DayGoal(kcal: 2200, goal: 2000), .onTarget)   // 110%
        XCTAssertEqual(DayGoal(kcal: 1690, goal: 2000), .offTarget)
        XCTAssertEqual(DayGoal(kcal: 2210, goal: 2000), .offTarget)
    }

    func testStreakCountsBackFromYesterdayUntilTodayIsInRange() {
        let goal = 2000.0
        let meals = [meal(kcal: 2000, daysAgo: 1), meal(kcal: 1900, daysAgo: 2), meal(kcal: 500, daysAgo: 3)]
        let streak = StreakSummary.make(meals: meals, goal: goal)
        XCTAssertEqual(streak.days, 2)
        XCTAssertEqual(streak.week.count, 7)
        // Oldest first, ending today: 3 days ago off (500), 2 and 1 days ago on, today nothing yet.
        XCTAssertEqual(Array(streak.week.suffix(4)), [false, true, true, false])
        XCTAssertEqual(StreakSummary.make(meals: meals + [meal(kcal: 2000)], goal: goal).days, 3)
    }

    func testDailyAverageIgnoresEmptyDays() {
        let meals = [meal(kcal: 1000), meal(kcal: 500), meal(kcal: 2000, daysAgo: 3)]
        XCTAssertEqual(ProfileView.dailyAverage(meals), 1750, accuracy: 0.001)
        XCTAssertEqual(ProfileView.dailyAverage([]), 0)
    }

    // MARK: Season

    func testSeasonFlipsInTheSouthernHemisphere() throws {
        let july = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15)))
        XCTAssertEqual(Season(date: july, latitude: 40).kind, .summer)
        XCTAssertEqual(Season(date: july, latitude: nil).kind, .summer)
        XCTAssertEqual(Season(date: july, latitude: -33).kind, .winter)
    }

    // MARK: Water from food

    func testFoodWaterUsesUSDAWaterThenEstimates() {
        let withWater = MealEntry(); withWater.servingSize = 100; withWater.water = 70
        XCTAssertEqual(FoodWater.grams(in: withWater), 70)
        let coffee = MealEntry(); coffee.servingSize = 250; coffee.calories = 2
        XCTAssertEqual(FoodWater.grams(in: coffee), 247.5, accuracy: 0.001)
        let steak = MealEntry(); steak.servingSize = 100; steak.protein = 21; steak.totalFat = 8
        XCTAssertEqual(FoodWater.grams(in: steak), 70, accuracy: 0.001)   // 100 − 29 solids − 1 ash
    }
}
