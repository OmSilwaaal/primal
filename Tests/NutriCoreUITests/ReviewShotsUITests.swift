import XCTest

/// Screens to look at after a change: the Raw guide, the Map filters, the goal editor.
final class ReviewShotsUITests: XCTestCase {
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

    func testRawGuide() {
        let app = launch("data")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Macros'")).firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        for _ in 0..<3 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45))
                .press(forDuration: 0.02, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45)),
                       withVelocity: .fast, thenHoldForDuration: 0)
            sleep(1)
        }
        let raw = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Raw'")).firstMatch
        XCTAssertTrue(raw.waitForExistence(timeout: 3))
        sleep(1)
        shot(app, "r1-raw-card")
        raw.tap()
        XCTAssertTrue(app.staticTexts["Water-soluble vitamins"].waitForExistence(timeout: 5))
        sleep(1)
        shot(app, "r2-raw-sheet")
        app.swipeUp()
        sleep(1)
        shot(app, "r3-raw-sheet-history")
    }

    func testMapFiltersAndGoalEditor() {
        let map = launch("map")
        sleep(3)
        XCTAssertFalse(map.buttons["Raw Meat"].exists)
        shot(map, "r4-map")
        let app = launch("profile")
        let tile = app.buttons["Goals this month"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        app.buttons["Add goal"].firstMatch.tap()
        XCTAssertTrue(app.switches.matching(NSPredicate(format: "label CONTAINS 'Apple Calendar'")).firstMatch.waitForExistence(timeout: 5))
        app.swipeUp()
        sleep(1)
        shot(app, "r5-goal-editor")
    }
}
