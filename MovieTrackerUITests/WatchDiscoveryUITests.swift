import XCTest

final class WatchDiscoveryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testFiltersPickAndDetailsBackPreserveCurrentChoice() {
        let app = launch()
        choose("Media type", identifier: "discovery.media", option: "Movies", app: app)
        XCTAssertTrue(app.staticTexts["1 eligible title"].waitForExistence(timeout: 5))
        tap(app.buttons["discovery.pick"], app)
        XCTAssertEqual(app.staticTexts["discovery.result.title"].label, "A Quiet Evening")
        tap(app.buttons["discovery.details"], app)
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        app.navigationBars["Details"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["discovery.result.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["discovery.result.title"].label, "A Quiet Evening")
        tap(app.buttons["discovery.filters"], app)
        XCTAssertTrue(app.staticTexts["1 eligible title"].waitForExistence(timeout: 5))
        tap(app.buttons["discovery.current"], app)
        XCTAssertEqual(app.staticTexts["discovery.result.title"].label, "A Quiet Evening")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Local discovery — deterministic movie pick"
        shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testCollectionSourceCanPickWatchedTitleAndSurvivesReturningToLibrary() {
        let app = launch()
        choose("Choose from", identifier: "discovery.source", option: "Movie Night", app: app)
        XCTAssertTrue(app.staticTexts["1 eligible title"].waitForExistence(timeout: 5))
        tap(app.buttons["discovery.pick"], app)
        XCTAssertEqual(app.staticTexts["discovery.result.title"].label, "An Old Favorite")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(app.buttons["library.discovery"], app)
        XCTAssertTrue(app.staticTexts["discovery.result.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["discovery.result.title"].label, "An Old Favorite")
        XCTAssertTrue(app.staticTexts["Next pick from: Movie Night"].exists)
    }

    @MainActor func testTVRuntimeEmptyStateAndResetFilters() {
        let app = launch()
        choose("Media type", identifier: "discovery.media", option: "TV Shows", app: app)
        choose("Movie runtime", identifier: "discovery.runtime", option: "Up to 90 minutes", app: app)
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["discovery.pick"].isEnabled)
        tap(app.buttons["discovery.clearFilters"], app)
        XCTAssertTrue(app.staticTexts["2 eligible titles"].waitForExistence(timeout: 5))
    }

    @MainActor func testGenreORAndYearFiltersCanBeCleared() {
        let app = launch()
        tap(app.buttons["Genres — 0 selected"], app)
        tap(app.switches["discovery.genre.drama"], app)
        XCTAssertTrue(app.staticTexts["1 eligible title"].waitForExistence(timeout: 5))
        tap(app.switches["discovery.genre.comedy"], app)
        XCTAssertTrue(app.staticTexts["2 eligible titles"].waitForExistence(timeout: 5))
        let year = app.textFields["discovery.firstYear"]
        tap(year, app); year.typeText("2021")
        tap(app.buttons["discovery.keyboardDone"], app)
        XCTAssertTrue(app.staticTexts["1 eligible title"].waitForExistence(timeout: 5))
        tap(app.buttons["discovery.pick"], app)
        XCTAssertEqual(app.staticTexts["discovery.result.title"].label, "One More Episode")
        tap(app.buttons["discovery.filters"], app)
        tap(app.buttons["discovery.clearFilters"], app)
        XCTAssertTrue(app.staticTexts["2 eligible titles"].waitForExistence(timeout: 5))
    }

    @MainActor func testEmptyWatchlistIsActionable() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing-search"]
        app.launch(); XCTAssertTrue(app.navigationBars["Your screen"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap()
        tap(app.buttons["library.discovery"], app)
        XCTAssertTrue(app.staticTexts["Nothing to pick yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["discovery.pick"].isEnabled)
        tap(app.buttons["Return to Library"], app)
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
    }

    @MainActor func testLargestTextDarkResultActionsRemainReachableAndTabStateIsPreserved() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"])
        choose("Media type", identifier: "discovery.media", option: "Movies", app: app)
        tap(app.buttons["discovery.pick"], app)
        let title = app.staticTexts["discovery.result.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5)); XCTAssertEqual(title.label, "A Quiet Evening")
        let details = app.buttons["discovery.details"]
        reveal(details, app)
        XCTAssertGreaterThanOrEqual(details.frame.height, 44)
        let filters = app.buttons["discovery.filters"]
        reveal(filters, app)
        XCTAssertLessThanOrEqual(filters.frame.maxY, app.tabBars.firstMatch.frame.minY)
        app.tabBars.buttons["Home"].tap(); app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["What Should I Watch?"].exists)
        reveal(title, app); XCTAssertEqual(title.label, "A Quiet Evening")
        tap(app.buttons["discovery.filters"], app)
        let clear = app.buttons["discovery.clearFilters"]
        reveal(clear, app)
        XCTAssertLessThanOrEqual(clear.frame.maxY, app.tabBars.firstMatch.frame.minY)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Discovery — largest text, dark, filter scroll end"
        shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testYearKeyboardDismissalAndResultIdentityInLightMode() {
        let app = launch(extra: ["-AppleInterfaceStyle", "Light"])
        let year = app.textFields["discovery.firstYear"]
        tap(year, app); year.typeText("2021")
        XCTAssertTrue(app.buttons["discovery.keyboardDone"].isHittable)
        app.buttons["discovery.keyboardDone"].tap()
        tap(app.buttons["discovery.pick"], app)
        XCTAssertEqual(app.staticTexts["discovery.result.title"].label, "One More Episode")
        tap(app.buttons["discovery.again"], app)
        XCTAssertEqual(app.staticTexts["discovery.result.title"].label, "One More Episode")
        tap(app.buttons["discovery.details"], app)
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        app.navigationBars["Details"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["discovery.result.title"].waitForExistence(timeout: 5))
    }

    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "--ui-testing-watch-discovery", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch(); XCTAssertTrue(app.navigationBars["Your screen"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap(); tap(app.buttons["library.discovery"], app)
        XCTAssertTrue(app.staticTexts["2 eligible titles"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func choose(_ label: String, identifier: String, option: String, app: XCUIApplication) {
        let picker = app.buttons[identifier].exists ? app.buttons[identifier] : app.buttons[label]
        tap(picker, app); tap(app.buttons[option], app)
    }
    @MainActor private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        reveal(element, app)
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable); element.tap()
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<25 {
            if element.isHittable { return }
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable)
    }
}
