import XCTest

final class SearchTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSearchMixedResultsSelectionAndStatePreservation() {
        let app = launchSearch()
        search("sample", in: app)
        let movie = result("movie.fixture:1", in: app)
        let show = result("tvShow.fixture:1", in: app)
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        XCTAssertTrue(show.exists)
        XCTAssertTrue(movie.label.contains("Movie"))
        XCTAssertTrue(show.label.contains("TV Show"))
        screenshot("Search — mixed fixture results", app: app)
        reveal(movie, in: app)
        movie.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sample Story"].exists)
        XCTAssertTrue(app.staticTexts["Movie"].exists)
        screenshot("Search — selected movie", app: app)
        app.navigationBars["Details"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(movie.exists)
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "sample")
    }

    @MainActor
    func testClearingSearchRemovesResults() {
        let app = launchSearch()
        search("sample", in: app)
        XCTAssertTrue(result("movie.fixture:1", in: app).waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch
        field.tap()
        field.buttons["Clear text"].tap()
        XCTAssertTrue(app.staticTexts["Find your next story"].waitForExistence(timeout: 5))
        XCTAssertFalse(result("movie.fixture:1", in: app).exists)
    }

    @MainActor
    func testFiltersAndPagination() {
        let app = launchSearch()
        search("sample", in: app)
        XCTAssertTrue(result("movie.fixture:1", in: app).waitForExistence(timeout: 5))
        let filters = app.segmentedControls["search.filters"]
        filters.buttons["Movies"].tap()
        XCTAssertTrue(result("movie.fixture:1", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(result("tvShow.fixture:1", in: app).exists)
        filters.buttons["TV Shows"].tap()
        XCTAssertTrue(result("tvShow.fixture:1", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(result("movie.fixture:1", in: app).exists)
        filters.buttons["All"].tap()
        XCTAssertTrue(result("movie.fixture:1", in: app).waitForExistence(timeout: 5))
        let more = app.buttons["search.loadMore"]
        reveal(more, in: app)
        more.tap()
        XCTAssertTrue(result("movie.fixture:2", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "search.result.movie.fixture:1").count, 1)
        XCTAssertFalse(more.exists)
    }

    @MainActor
    func testEmptyResults() {
        let app = launchSearch()
        search("empty", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["search.empty"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["search.error"].firstMatch.exists)
        screenshot("Search — empty fixture response", app: app)
    }

    @MainActor
    func testErrorAndExplicitRetry() {
        let app = launchSearch()
        search("retry", in: app)
        let error = app.descendants(matching: .any)["search.error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["An internet connection is required to retrieve metadata."].exists)
        XCTAssertFalse(app.descendants(matching: .any)["search.empty"].firstMatch.exists)
        screenshot("Search — offline fixture error", app: app)
        let retry = app.buttons["search.retry"]
        reveal(retry, in: app)
        retry.tap()
        XCTAssertTrue(result("movie.fixture:1", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(error.exists)
    }

    @MainActor
    private func launchSearch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(app.staticTexts["UI test data"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func search(_ text: String, in app: XCUIApplication) {
        let field = app.searchFields["Movies and TV shows"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    @MainActor
    private func result(_ suffix: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["search.result." + suffix]
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
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
