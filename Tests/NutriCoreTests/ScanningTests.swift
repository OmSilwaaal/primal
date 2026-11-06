import XCTest
@testable import NutriCore

/// Barcode and photo scanning: code formats, unit conversions, and how a photo's foods become a meal.
final class ScanningTests: XCTestCase {

    // MARK: Barcode formats

    func testSearchFormsCoverEveryStoredLength() {
        // The camera reads a US UPC-A as a 13-digit EAN with a leading 0; USDA stores the 12-digit form.
        XCTAssertEqual(BarcodeLookupService.searchForms("0016000348516"),
                       ["0016000348516", "016000348516", "00016000348516"])
        XCTAssertEqual(BarcodeLookupService.searchForms("5000159484695"), ["5000159484695", "05000159484695"])
        XCTAssertEqual(BarcodeLookupService.searchForms("abc"), [])
    }

    func testUPCEExpandsToUPCA() {
        XCTAssertEqual(BarcodeLookupService.expandedUPCE("04252614"), "042100005264")
        XCTAssertEqual(BarcodeLookupService.expandedUPCE("01234565"), "012345000065")
        XCTAssertNil(BarcodeLookupService.expandedUPCE("0016000348516"))
        XCTAssertNil(BarcodeLookupService.expandedUPCE("31234565"))   // number system must be 0 or 1
    }

    // MARK: Open Food Facts units

    func testOpenFoodFactsGramsBecomeUSDAUnits() {
        // Real values from Twix glacé (5000159484695): every _100g value is in grams.
        let raw: [String: Double] = ["energy-kcal_100g": 280.74, "proteins_100g": 3.5, "fat_100g": 14,
                                     "vitamin-a_100g": 6e-05, "calcium_100g": 0.08, "sodium_100g": 0.1021,
                                     "vitamin-b12_100g": 2e-07, "iron_100g": 0.0012]
        let items = BarcodeLookupService.nutrients(from: { raw[$0] })
        func value(_ id: Int) -> Double? { items.first { $0.nutrientId == id }?.value }
        XCTAssertEqual(value(1008)!, 280.74, accuracy: 0.001)
        XCTAssertEqual(value(1106)!, 60, accuracy: 0.001)      // vitamin A, mcg
        XCTAssertEqual(value(1087)!, 80, accuracy: 0.001)      // calcium, mg
        XCTAssertEqual(value(1093)!, 102.1, accuracy: 0.001)   // sodium, mg
        XCTAssertEqual(value(1178)!, 0.2, accuracy: 0.0001)    // B12, mcg
        XCTAssertEqual(value(1089)!, 1.2, accuracy: 0.0001)    // iron, mg
        XCTAssertNil(value(1114))                               // not listed, not invented
    }

    func testOpenFoodFactsEnergyAndSodiumFallbacks() {
        let raw: [String: Double] = ["energy_100g": 1801.28, "salt_100g": 1.25]
        let items = BarcodeLookupService.nutrients(from: { raw[$0] })
        XCTAssertEqual(items.first { $0.nutrientId == 1008 }!.value, 430.5, accuracy: 0.1)   // kJ → kcal
        XCTAssertEqual(items.first { $0.nutrientId == 1093 }!.value, 500, accuracy: 0.1)     // salt ÷ 2.5, mg
    }

    func testBrandedGramServingUnits() {
        let grm = FoodSearchResult(fdcId: 1, description: "x", servingSize: 52, servingSizeUnit: "GRM", foodNutrients: [])
        XCTAssertEqual(grm.defaultServingGrams, 52)
        let ml = FoodSearchResult(fdcId: 1, description: "x", servingSize: 240, servingSizeUnit: "MLT", foodNutrients: [])
        XCTAssertEqual(ml.defaultServingGrams, 100)
    }

    func testEnergyFromMacrosWhenUSDAListsNone() {
        // "Butter, stick, salted" (Foundation) has no energy IDs at all.
        let butter = FoodSearchResult(fdcId: 1, description: "Butter, stick, salted", dataType: "Foundation",
                                      foodNutrients: [FoodNutrientItem(nutrientId: 1004, value: 81),
                                                      FoodNutrientItem(nutrientId: 1003, value: 0.9)])
        XCTAssertEqual(butter.energyKcal, 732.6, accuracy: 0.01)
    }

    // MARK: Photo → meal

    private func item(_ name: String, _ query: String, _ grams: Double, raw: Bool = true,
                      kcal: Double, p: Double = 0, c: Double = 0, f: Double = 0) -> PhotoMeal.Item {
        .init(name: name, usdaQuery: query, grams: grams, raw: raw, kcal: kcal, protein: p, carbs: c, fat: f)
    }

    private func usda(_ description: String, _ nutrients: [Int: Double], type: String = "SR Legacy") -> FoodSearchResult {
        FoodSearchResult(fdcId: 1, description: description, dataType: type,
                         foodNutrients: nutrients.map { FoodNutrientItem(nutrientId: $0.key, value: $0.value) })
    }

    func testParseToleratesFencesAndDropsEmptyItems() throws {
        let text = """
        ```json
        {"items": [{"name": "Ribeye steak", "usdaQuery": "Beef, ribeye, steak, raw", "grams": 220, "raw": true,
                    "kcal": 560, "protein": 48, "carbs": 0, "fat": 40},
                   {"name": "", "usdaQuery": "", "grams": 10, "raw": false, "kcal": 1, "protein": 0, "carbs": 0, "fat": 0}]}
        ```
        """
        let items = try PhotoMeal.parse(text)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].grams, 220)
        XCTAssertTrue(items[0].raw)
        XCTAssertEqual(try PhotoMeal.parse(#"{"items": []}"#), [])
    }

    func testMatcherPrefersAgreeingCompleteRawRecord() {
        let steak = item("Ribeye steak", "Beef, ribeye, steak, raw", 220, kcal: 560)
        let full: [Int: Double] = (1000...1100).reduce(into: [1008: 250]) { $0[$1] = $0[$1] ?? 1 }
        let candidates = [
            usda("Beef, ribeye, steak, boneless, choice, raw", [2047: 254, 1003: 18], type: "Foundation"),   // few nutrients
            usda("Beef, ribeye, steak, separable lean and fat, raw", full),
            usda("Beef, ribeye, steak, cooked, grilled", [1008: 290, 1003: 26]),
        ]
        XCTAssertEqual(PhotoMeal.bestMatch(for: steak, in: candidates)?.description,
                       "Beef, ribeye, steak, separable lean and fat, raw")
    }

    func testMatcherRejectsWrongFoodByEnergy() {
        // "oyster" also matches oyster mushrooms (33 kcal/100 g); the model said ~65 kcal for 80 g of oysters.
        let oysters = item("Oysters", "Mollusks, oyster, raw", 80, kcal: 65)
        XCTAssertNil(PhotoMeal.bestMatch(for: oysters, in: [usda("Mushrooms, oyster, raw", [1008: 33])]))
        XCTAssertNotNil(PhotoMeal.bestMatch(for: oysters, in: [usda("Mollusks, oyster, Pacific, raw", [1008: 81])]))
        XCTAssertNil(PhotoMeal.bestMatch(for: oysters, in: [usda("Cereal, honey roasted oats", [1008: 400])]))
    }

    func testCombineWeightsEachPartAndFallsBackToModelMacros() {
        let liver = item("Beef liver", "Beef, liver, raw", 100, kcal: 135)
        let honey = item("Honey", "Honey", 20, raw: false, kcal: 61, c: 16.5)
        let meal = PhotoMeal.combine([
            (item: liver, match: usda("Beef, variety meats and by-products, liver, raw", [1008: 135, 1178: 59.3, 1106: 4970])),
            (item: honey, match: nil),   // no match: the model's numbers
        ])
        // Per 100 g of the 120 g plate.
        XCTAssertEqual(meal.servingSize, 120)
        XCTAssertEqual(meal.energyKcal, (135 + 61) / 1.2, accuracy: 0.01)
        XCTAssertEqual(meal.nutrient(1178), 59.3 / 1.2, accuracy: 0.01)
        XCTAssertEqual(meal.nutrient(1005), 16.5 / 1.2, accuracy: 0.01)
        // Logging the whole plate gives back the parts' totals.
        let entry = MealEntry(from: meal, servingSize: 120)
        XCTAssertEqual(entry.calories, 196, accuracy: 0.01)
        XCTAssertEqual(entry.vitaminB12, 59.3, accuracy: 0.01)
        XCTAssertEqual(entry.source, "Photo + USDA")
        XCTAssertEqual(meal.description, "Beef liver + honey")
    }

    func testAllRawPlateIsNamedRaw() {
        let names = PhotoMeal.name(for: [item("Ribeye steak", "", 200, kcal: 500), item("Egg yolks", "", 34, kcal: 110)])
        XCTAssertEqual(names, "Ribeye steak + egg yolks, raw")
        let meal = MealEntry(); meal.foodName = names
        XCTAssertTrue(meal.isRawFood, "the Raw card must count a raw plate")
    }

    // MARK: Live (real USDA and Open Food Facts). Run with TEST_RUNNER_LIVE_SERVICES=1.

    private var live: Bool { ProcessInfo.processInfo.environment["LIVE_SERVICES"] == "1" }

    func testLiveBarcodes() async throws {
        try XCTSkipUnless(live, "set TEST_RUNNER_LIVE_SERVICES=1 to call the real services")
        // Cheerios as the camera reads it (13 digits) must now hit USDA Branded, not fall back.
        let cheerios = try await BarcodeLookupService.resolve("0016000348516")
        XCTAssertEqual(cheerios?.dataType, "Branded")
        XCTAssertGreaterThan(cheerios?.nutrient(1089) ?? 0, 20)   // fortified iron, mg/100 g
        // A European product only Open Food Facts has.
        let twix = try await BarcodeLookupService.resolve("5000159484695")
        XCTAssertEqual(twix?.dataType, "Open Food Facts")
        XCTAssertEqual(twix?.nutrient(1106) ?? 0, 60, accuracy: 1)   // vitamin A, mcg
    }

    func testLivePhotoPlateMatchesUSDA() async throws {
        try XCTSkipUnless(live, "set TEST_RUNNER_LIVE_SERVICES=1 to call the real services")
        // What the model would return for a raw-diet plate.
        let plate = [
            item("Ribeye steak", "Beef, ribeye, steak, raw", 220, kcal: 560, p: 44, f: 42),
            item("Beef liver", "Beef, variety meats and by-products, liver, raw", 60, kcal: 81, p: 12, c: 2, f: 2),
            item("Egg yolks", "Egg, yolk, raw, fresh", 34, kcal: 110, p: 5, f: 9),
            item("Oysters", "Mollusks, oyster, Pacific, raw", 80, kcal: 65, p: 8, c: 4, f: 2),
            item("Butter", "Butter, salted", 14, raw: false, kcal: 100, f: 11),
            item("Blueberries", "Blueberries, raw", 75, kcal: 43, c: 11),
        ]
        let result = await PhotoMeal.resolve(plate)
        XCTAssertEqual(result.matched, plate.count, "every food should find a USDA record")
        let entry = MealEntry(from: result.food, servingSize: result.grams)
        print("LIVE plate:", Int(entry.calories), "kcal ·", Int(entry.protein), "g protein ·",
              "B12", entry.vitaminB12, "mcg · A", Int(entry.vitaminA), "mcg · zinc", entry.zinc, "mg")
        XCTAssertEqual(entry.calories, 959, accuracy: 959 * 0.25)   // the model's own total, within 25%
        XCTAssertGreaterThan(entry.vitaminB12, 30)                  // liver + oysters
        XCTAssertGreaterThan(entry.vitaminA, 2000)                  // liver
        XCTAssertGreaterThan(entry.zinc, 20)                        // oysters
    }
}

/// What logging does to the day: liquids and nutrients from every way a food can be added.
final class LoggingEffectTests: XCTestCase {
    private func usda(_ description: String, _ nutrients: [Int: Double]) -> FoodSearchResult {
        FoodSearchResult(fdcId: 1, description: description, dataType: "SR Legacy",
                         foodNutrients: nutrients.map { FoodNutrientItem(nutrientId: $0.key, value: $0.value) })
    }

    func testDrinksAndFoodsAddTheirWater() {
        // Whole milk, raw: 87.7 g water per 100 g (USDA 1051).
        let milk = MealEntry(from: usda("Milk, whole, raw", [1008: 61, 1051: 87.7, 1003: 3.2, 1004: 3.3, 1005: 4.8]), servingSize: 250)
        XCTAssertEqual(FoodWater.grams(in: milk), 219.25, accuracy: 0.01)
        // Ribeye with no water listed: estimated from what isn't protein, fat or carbs.
        let steak = MealEntry(from: usda("Beef, ribeye, raw", [1008: 254, 1003: 18, 1004: 20]), servingSize: 200)
        XCTAssertEqual(FoodWater.grams(in: steak), 200 - 36 - 40 - 2, accuracy: 0.01)
        XCTAssertEqual(FoodWater.millilitres(in: [milk, steak]), 219.25 + 122, accuracy: 0.01)
    }

    func testPhotoMealChangesTheNutrientProfile() {
        let goals = NutrientGoals.default
        let before = buildNutrientList(from: [], goals: goals)
        let liver = PhotoMeal.Item(name: "Beef liver", usdaQuery: "Beef, liver, raw", grams: 100, raw: true,
                                   kcal: 135, protein: 20, carbs: 4, fat: 4)
        let meal = PhotoMeal.combine([(item: liver, match: usda("Beef, variety meats and by-products, liver, raw",
            [1008: 135, 1003: 20.4, 1178: 59.3, 1106: 4970, 1089: 4.9, 1098: 9.76, 1051: 70.8]))])
        let entry = MealEntry(from: meal, servingSize: 100)
        let after = buildNutrientList(from: [entry], goals: goals)
        func value(_ id: String, _ list: [NutrientInfo]) -> Double { list.first { $0.id == id }!.current }
        XCTAssertEqual(value("b12", before), 0)
        XCTAssertEqual(value("b12", after), 59.3, accuracy: 0.01)
        XCTAssertEqual(value("va", after), 4970, accuracy: 0.01)
        XCTAssertEqual(value("fe", after), 4.9, accuracy: 0.01)
        XCTAssertEqual(value("cu", after), 9.76, accuracy: 0.01)
        XCTAssertEqual(FoodWater.grams(in: entry), 70.8, accuracy: 0.01)   // and its water
        // The Raw card counts it as raw organ meat.
        let raw = buildRawList(from: [entry], isMale: true)
        XCTAssertEqual(raw.first { $0.id == "raw" }!.current, 100)
        XCTAssertEqual(raw.first { $0.id == "org" }!.current, 100)
    }
}
