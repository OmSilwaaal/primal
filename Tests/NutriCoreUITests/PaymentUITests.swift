import XCTest

/// Buying Vitalis Pro through the real Payment page and Apple's buy sheet, against the local App Store.
final class PaymentUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testSubscribeFromSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestTabs", "-uiTestTab", "profile"]
        app.launch()

        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let getPro = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Get Vitalis Pro'")).firstMatch
        if !getPro.waitForExistence(timeout: 5),
           app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vitalis Pro'")).firstMatch.exists {
            throw XCTSkip("Already a member on this simulator (an earlier run's purchase); delete the app to reset.")
        }
        XCTAssertTrue(getPro.exists)
        shot(app, "pay-1-settings")
        getPro.tap()

        let subscribe = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Subscribe'")).firstMatch
        guard subscribe.waitForExistence(timeout: 10) else {
            shot(app, "pay-2-no-prices")
            throw XCTSkip("No prices: the local App Store isn't attached to this test run")
        }
        shot(app, "pay-2-payment")
        subscribe.tap()

        // Apple's buy sheet: in the app's process with StoreKit testing, else SpringBoard's.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirm = [app, springboard].lazy.map { $0.buttons["Subscribe"].firstMatch }
            .first { $0.waitForExistence(timeout: 6) && $0.label == "Subscribe" && $0.isHittable }
        shot(app, "pay-3-sheet")
        try XCTUnwrap(confirm, "buy sheet").tap()
        for host in [app, springboard] where host.buttons["OK"].waitForExistence(timeout: 4) { host.buttons["OK"].tap() }

        XCTAssertTrue(app.staticTexts["Your membership"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Manage subscription"].exists)
        shot(app, "pay-4-member")
    }
}
