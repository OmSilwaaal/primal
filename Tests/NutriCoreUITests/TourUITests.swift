import XCTest

/// Opens every screen that's a few taps deep and checks it appears (and doesn't crash), saving a screenshot of
/// each when SHOTS_DIR is set.
final class TourUITests: XCTestCase {
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

    func testSettingsAndLegal() {
        let app = launch("profile")
        sleep(2)
        shot(app, "t0-profile")
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        shot(app, "t1-settings")
        app.swipeUp(); app.swipeUp()
        shot(app, "t1b-settings-bottom")
        let legal = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Legal & support'")).firstMatch
        XCTAssertTrue(legal.waitForExistence(timeout: 5))
        legal.tap()
        XCTAssertTrue(app.staticTexts["Legal & support"].waitForExistence(timeout: 5))
        shot(app, "t2-legal")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Privacy policy'")).firstMatch.tap()
        sleep(2)
        shot(app, "t3-privacy")
    }

    func testRedoSetupOpensFromSettings() {
        let app = launch("profile")
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let redo = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Redo setup'")).firstMatch
        XCTAssertTrue(redo.waitForExistence(timeout: 5))
        redo.tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
        sleep(1)
        shot(app, "t6-setup")
    }

    func testDataSheet() {
        let data = launch("data")
        let card = data.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Macros'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        sleep(2)
        shot(data, "t5-data-sheet")
    }
}
