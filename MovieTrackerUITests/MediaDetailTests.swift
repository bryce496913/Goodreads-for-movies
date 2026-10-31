import XCTest

final class MediaDetailUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testMovieDetailsAndBackNavigation() {
        let app = launchDetails(kind: "movie")
        XCTAssertTrue(app.staticTexts["details.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Movie information"].exists)
        screenshot("Details — movie fixture", app: app)
        let runtime = app.descendants(matching: .any).matching(identifier: "details.fact.Runtime").firstMatch
        reveal(runtime, in: app)
        XCTAssertTrue(runtime.label.contains("98 min"))
        let cast = app.descendants(matching: .any).matching(identifier: "details.cast.fixture:cast1").firstMatch
        reveal(cast, in: app)
        XCTAssertTrue(cast.label.contains("Sample Performer"))
        app.navigationBars["Details"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search.result.movie.fixture:1"].exists)
    }

    @MainActor
    func testTVDetailsAndNoninteractiveSeasonSummary() {
        let app = launchDetails(kind: "tvShow")
        XCTAssertTrue(app.staticTexts["details.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Series information"].exists)
        screenshot("Details — television fixture", app: app)
        let seasons = app.descendants(matching: .any).matching(identifier: "details.fact.Seasons").firstMatch
        reveal(seasons, in: app)
        XCTAssertTrue(seasons.label.contains("3"))
        let episodes = app.descendants(matching: .any).matching(identifier: "details.fact.Episodes").firstMatch
        reveal(episodes, in: app)
        XCTAssertTrue(episodes.label.contains("24"))
        XCTAssertFalse(app.buttons["Track Episode"].exists)
    }

    @MainActor
    func testMissingMetadataAndArtworkFallbacks() {
        let app = launchDetails(kind: "movie", mode: "missing")
        XCTAssertTrue(app.staticTexts["details.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.images["details.backdrop.placeholder"].exists)
        XCTAssertTrue(app.images["details.poster.placeholder"].exists)
        let synopsis = app.staticTexts["details.synopsis"]
        reveal(synopsis, in: app)
        XCTAssertEqual(synopsis.label, "No synopsis available.")
        let cast = app.staticTexts["No cast information available."]
        reveal(cast, in: app)
        XCTAssertTrue(cast.exists)
        screenshot("Details — missing metadata fixture", app: app)
    }

    @MainActor
    func testNetworkErrorAndExplicitRetry() {
        let app = launchDetails(kind: "movie", mode: "retry")
        let error = app.descendants(matching: .any).matching(identifier: "details.error").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        let retry = app.buttons["details.retry"]
        reveal(retry, in: app)
        retry.tap()
        XCTAssertTrue(app.staticTexts["details.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(error.exists)
    }

    @MainActor
    func testOfflineReopenKeepsPreviouslyLoadedDetails() {
        let app = launchDetails(kind: "movie", mode: "offline-after-load")
        XCTAssertTrue(app.staticTexts["details.title"].waitForExistence(timeout: 5))
        app.navigationBars["Details"].buttons.element(boundBy: 0).tap()
        let result = app.buttons["search.result.movie.fixture:1"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.staticTexts["details.cached"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["details.title"].label, "Sample Story")
    }

    @MainActor
    func testLongTitleAndSynopsisAtAccessibilitySizeInDarkMode() {
        let app = launchDetails(kind: "tvShow", mode: "long", accessibility: true)
        let title = app.staticTexts["details.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(title.label.count, 100)
        let synopsis = app.staticTexts["details.synopsis"]
        reveal(synopsis, in: app)
        XCTAssertGreaterThan(synopsis.label.count, 400)
        let footer = app.buttons["details.retry"]
        reveal(footer, in: app)
        XCTAssertTrue(footer.isHittable)
        screenshot("Details — large text dark fixture", app: app)
    }

    @MainActor
    private func launchDetails(kind: String, mode: String = "complete", accessibility: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "--detail-fixture=" + mode]
        if accessibility {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                                    "-AppleInterfaceStyle", "Dark"]
        }
        app.launch()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields["Movies and TV shows"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("sample")
        let result = app.buttons["search.result." + kind + ".fixture:1"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        reveal(result, in: app)
        result.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<60 {
            if element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
