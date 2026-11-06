import XCTest

/// The Data sheet's per-food breakdown, History's meal detail, and swiping the wheel.
final class DataDetailUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func launch(_ tab: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestTabs", "-uiTestTab", tab]
        app.launch()
        return app
    }

    func testNutrientDropsDownItsFoods() {
        let app = launch("data")
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Macros'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let calories = app.buttons["Calories"].firstMatch
        XCTAssertTrue(calories.waitForExistence(timeout: 5))
        calories.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Where it came from today'")).firstMatch.waitForExistence(timeout: 3))
        sleep(1)
        shot(app, "d1-breakdown")
    }

    func testHistoryMealOpensItsDetail() {
        let app = launch("profile")
        let history = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'History'")).firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        history.tap()
        let meal = app.buttons.matching(NSPredicate(format: "label CONTAINS 'kcal'")).firstMatch
        XCTAssertTrue(meal.waitForExistence(timeout: 5))
        meal.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Vitamins and minerals'")).firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        shot(app, "d2-meal")
    }

    func testEachSwipeTurnsOneCard() {
        let app = launch("data")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Macros'")).firstMatch.waitForExistence(timeout: 10))
        sleep(2)
        // Only the centred card is visible to accessibility, so its button names where the wheel is.
        for expected in ["Vitamins", "Minerals", "Raw"] {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45))
            from.press(forDuration: 0.02, thenDragTo: to, withVelocity: .fast, thenHoldForDuration: 0)
            let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(expected),")).firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 3), "after a swipe the wheel should be on \(expected)")
        }
        shot(app, "d3-after-swipes")
    }
}
