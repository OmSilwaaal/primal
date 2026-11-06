import XCTest

/// The first-run path as a guest: welcome, the policies to agree to, the paywall, then the app.
final class FirstRunUITests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testGuestFirstRun() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestFresh"]
        app.launch()

        let skip = app.buttons["Skip"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        sleep(1)
        shot(app, "f1-welcome")
        skip.tap()

        let agree = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'I have read'")).firstMatch
        XCTAssertTrue(agree.waitForExistence(timeout: 5))
        shot(app, "f2-consent")
        agree.tap()
        app.buttons["I agree"].firstMatch.tap()

        // A guest sees the paywall once, unless this Apple Account already has Pro (then straight in).
        let notNow = app.buttons["Not now"].firstMatch
        if notNow.waitForExistence(timeout: 8) {
            sleep(1)
            shot(app, "f3-paywall")
            notNow.tap()
        }

        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 8))
        sleep(1)
        shot(app, "f4-home")
    }
}
