import XCTest

final class NavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTabsAndSettingsNavigation() async {
        let app = XCUIApplication()
        app.launch()
        assertScreen("Welcome", in: app)
        for title in ["Home", "Search", "Library", "Profile"] {
            XCTAssertTrue(app.tabBars.buttons[title].isHittable, "Missing tab: \(title)")
        }
        app.tabBars.buttons["Search"].tap()
        assertScreen("Search", in: app)
        XCTAssertTrue(app.searchFields["Movies and TV shows"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Library"].tap()
        assertScreen("Library", in: app)
        // Cards combine their title and message for VoiceOver; do not query a hidden child label.
        XCTAssertTrue(app.descendants(matching: .any)["library.watchlist"].firstMatch.exists)
        app.tabBars.buttons["Profile"].tap()
        assertScreen("Profile", in: app)
        openSettings(in: app)
        app.tabBars.buttons["Home"].tap()
        assertScreen("Welcome", in: app)
        app.tabBars.buttons["Profile"].tap()
        assertScreen("Settings", in: app)
        app.navigationBars["Settings"].buttons.element(boundBy: 0).tap()
        assertScreen("Profile", in: app)
    }

    @MainActor
    func testStartupBackgroundAndColdRelaunch() async {
        let app = XCUIApplication()
        app.launch()
        assertScreen("Welcome", in: app)
        app.tabBars.buttons["Library"].tap()
        assertScreen("Library", in: app)
        XCUIDevice.shared.press(.home)
        app.activate()
        assertScreen("Library", in: app)
        app.terminate()
        app.launch()
        assertScreen("Welcome", in: app)
        XCTAssertFalse(app.staticTexts["Library unavailable"].exists)
    }

    @MainActor
    func testSettingsReachableAtLargestAccessibilityTextSize() async {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()
        assertScreen("Welcome", in: app)
        app.tabBars.buttons["Profile"].tap()
        assertScreen("Profile", in: app)
        openSettings(in: app)
    }

    @MainActor
    private func assertScreen(
        _ title: String, in app: XCUIApplication,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(app.navigationBars.count, 1, "Expected one navigation bar", file: file, line: line)
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let settings = app.buttons["profile.settings"]
        // Scroll until the control is reachable, rather than assuming a particular screen height.
        for _ in 0..<8 {
            if settings.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        assertScreen("Settings", in: app)
        XCTAssertTrue(app.staticTexts["Settings coming soon"].exists)
    }
}
