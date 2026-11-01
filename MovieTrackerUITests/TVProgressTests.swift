import XCTest

final class TVProgressUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSeasonNavigationAndImmediateEpisodeToggle() {
        let app = openSeason()
        let toggle = app.switches["episode.toggle.fixture:episode:1:1"]
        reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.navigationBars["Season 1"].buttons.element(boundBy: 0).tap()
        let season = app.buttons["tv.season.1"]
        reveal(season, in: app)
        XCTAssertTrue(season.label.contains("Episodes marked watched: 1"))
    }

    @MainActor
    func testBatchWatchedAndUnwatchedSkipFutureEpisodes() {
        let app = openSeason()
        let watched = app.buttons["tv.batchWatched"]
        reveal(watched, in: app); watched.tap()
        app.sheets.buttons["Mark Aired Watched"].tap()
        let first = app.switches["episode.toggle.fixture:episode:1:1"]
        reveal(first, in: app)
        XCTAssertEqual(first.value as? String, "1")
        let unknown = app.switches["episode.toggle.fixture:episode:1:7"]
        reveal(unknown, in: app)
        XCTAssertEqual(unknown.value as? String, "0")
        let future = app.switches["episode.toggle.fixture:episode:1:8"]
        reveal(future, in: app)
        XCTAssertFalse(future.isEnabled)
        XCTAssertEqual(future.value as? String, "0")
        let unwatched = app.buttons["tv.batchUnwatched"]
        reveal(unwatched, in: app); unwatched.tap()
        app.sheets.buttons["Mark Unwatched"].tap()
        reveal(first, in: app)
        XCTAssertEqual(first.value as? String, "0")
    }

    @MainActor
    func testOfflineEpisodeMutationAfterPersistentRelaunch() {
        let app = openSeason(extra: ["--ui-testing-library-store=" + UUID().uuidString])
        let toggle = app.switches["episode.toggle.fixture:episode:1:1"]
        reveal(toggle, in: app); toggle.tap()
        app.terminate()
        app.launchArguments += ["--detail-fixture=error"]
        app.launch()
        openSavedSeason(in: app)
        XCTAssertTrue(app.staticTexts["tv.cached"].waitForExistence(timeout: 5))
        let saved = app.switches["episode.toggle.fixture:episode:1:1"]
        reveal(saved, in: app)
        XCTAssertEqual(saved.value as? String, "1")
        saved.tap()
        XCTAssertEqual(saved.value as? String, "0")
        app.terminate(); app.launch()
        openSavedSeason(in: app)
        let reopened = app.switches["episode.toggle.fixture:episode:1:1"]
        reveal(reopened, in: app)
        XCTAssertEqual(reopened.value as? String, "0")
    }

    @MainActor
    func testMovieDetailsDoNotOfferEpisodeTracking() {
        let app = launch(extra: [])
        searchAndOpen("movie", in: app)
        XCTAssertTrue(app.staticTexts["Movie information"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tv.season.")).count, 0)
    }

    @MainActor
    private func launch(extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func searchAndOpen(_ kind: String, in app: XCUIApplication) {
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields["Movies and TV shows"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("sample")
        let result = app.buttons["search.result." + kind + ".fixture:1"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        reveal(result, in: app); result.tap()
        XCTAssertTrue(app.staticTexts["details.title"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openSeason(extra: [String] = []) -> XCUIApplication {
        let app = launch(extra: extra)
        searchAndOpen("tvShow", in: app)
        let season = app.buttons["tv.season.1"]
        XCTAssertTrue(season.waitForExistence(timeout: 10))
        reveal(season, in: app); season.tap()
        XCTAssertTrue(app.navigationBars["Season 1"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func openSavedSeason(in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap()
        let row = app.buttons["library.row.tvShow.fixture:1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        reveal(row, in: app); row.tap()
        let season = app.buttons["tv.season.1"]
        XCTAssertTrue(season.waitForExistence(timeout: 5))
        reveal(season, in: app); season.tap()
        XCTAssertTrue(app.navigationBars["Season 1"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for direction in 0..<2 {
            for _ in 0..<20 {
                if element.isHittable { return }
                if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() }
                else if direction == 0 { app.swipeUp() } else { app.swipeDown() }
            }
        }
        XCTAssertTrue(element.isHittable)
    }
}
