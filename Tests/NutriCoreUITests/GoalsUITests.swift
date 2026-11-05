import XCTest

/// The Goals page: add a goal, see it on the chosen day, tick it off.
final class GoalsUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        // Saved next to the test run for a visual check (ignored if the folder isn't writable).
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testAddGoalShowsOnTheDayAndTicksOff() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestTabs", "-uiTestTab", "profile"]
        app.launch()

        let tile = app.buttons["Goals this month"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        tile.tap()
        XCTAssertTrue(app.staticTexts["Goals"].waitForExistence(timeout: 5))
        // The sample store's goals: Morning sun is due every day and done today.
        XCTAssertTrue(app.staticTexts["Morning sun"].waitForExistence(timeout: 3))
        shot(app, "goals-1-page")

        app.buttons["Add goal"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Raw liver\n")
        app.buttons["Once"].firstMatch.tap()
        shot(app, "goals-2-editor")
        // The sheet's own Add goal button (the page's is behind it).
        let save = app.buttons.matching(identifier: "Add goal").allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(save)
        save?.tap()

        XCTAssertTrue(app.staticTexts["Raw liver"].waitForExistence(timeout: 5))
        let notDone = app.buttons["Not done"].firstMatch
        XCTAssertTrue(notDone.exists)
        notDone.tap()
        sleep(1)
        shot(app, "goals-3-added")
    }
}
