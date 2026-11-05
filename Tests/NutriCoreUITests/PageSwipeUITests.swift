import XCTest

/// Swiping between pages from the screen edges, on the real app with the sample store.
final class PageSwipeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestTabs", "-uiTestTab", "data"]
        app.launch()
    }

    private func selected(_ tab: String) -> Bool { app.buttons[tab].firstMatch.isSelected }

    /// A drag from just inside one edge, a third of the way across, at mid height.
    private func swipe(fromRight: Bool) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: fromRight ? 0.985 : 0.015, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: fromRight ? 0.6 : 0.4, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    func testEdgeSwipesTurnPages() {
        XCTAssertTrue(app.buttons["Data"].waitForExistence(timeout: 10))
        XCTAssertTrue(selected("Data"))

        swipe(fromRight: true)                        // next: Profile
        XCTAssertTrue(app.buttons["Profile"].wait(for: \.isSelected, toEqual: true, timeout: 3))

        swipe(fromRight: true)                        // Profile is last: stays
        sleep(1)
        XCTAssertTrue(selected("Profile"))

        swipe(fromRight: false)                       // previous: Data
        XCTAssertTrue(app.buttons["Data"].wait(for: \.isSelected, toEqual: true, timeout: 3))
    }

    func testSwipingTheDataWheelDoesNotTurnThePage() {
        XCTAssertTrue(app.buttons["Data"].waitForExistence(timeout: 10))
        // A swipe in the middle of the screen belongs to the wheel.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(1)
        XCTAssertTrue(selected("Data"))
    }
}
