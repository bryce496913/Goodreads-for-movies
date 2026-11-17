import XCTest

@MainActor
final class ProviderBrowseUITests: XCTestCase {
    func testBrowseMediaCategoriesGenresAndDetailNavigation() {
        let app = launch()
        XCTAssertTrue(element("browse.result.movie.fixture:1", app).waitForExistence(timeout: 5))
        app.segmentedControls["browse.media"].buttons["TV Shows"].tap()
        XCTAssertTrue(element("browse.result.tvShow.fixture:1", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("browse.result.movie.fixture:1", app).exists)
        choose("Popular", app: app)
        XCTAssertTrue(element("browse.loadMore", app).waitForExistence(timeout: 5))
        choose("Top Rated", app: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "independent of your personal ratings")).firstMatch.exists)
        choose("Genres", app: app)
        element("browse.genres", app).tap()
        app.buttons["Comedy"].tap()
        XCTAssertTrue(element("browse.result.tvShow.fixture:1", app).waitForExistence(timeout: 5))
        element("browse.result.tvShow.fixture:1", app).tap()
        XCTAssertTrue(element("media.details", app).waitForExistence(timeout: 5))
        capture("040 TV browse to details", app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(element("browse.result.tvShow.fixture:1", app).waitForExistence(timeout: 5))
    }

    func testTypingAndClearingRestoresBrowse() {
        let app = launch()
        XCTAssertTrue(element("browse.result.movie.fixture:1", app).waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch
        field.tap(); field.typeText("sample")
        XCTAssertTrue(element("search.result.movie.fixture:1", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("browse.content", app).exists)
        field.buttons["Clear text"].tap()
        XCTAssertTrue(element("browse.result.movie.fixture:1", app).waitForExistence(timeout: 5))
        capture("040 Movie Browse", app)
    }

    func testOfflineIsFailureAndEmptyIsNotFailure() {
        var app = launch("browse-offline")
        XCTAssertTrue(element("browse.error", app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("browse.retry", app).exists)
        XCTAssertFalse(element("browse.empty", app).exists)
        app.terminate()
        app = launch("browse-empty")
        XCTAssertTrue(element("browse.empty", app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("browse.error", app).exists)
    }

    func testSimilarTitlesExcludeCurrentAndOpenExistingDetails() {
        let app = launch()
        XCTAssertTrue(element("browse.result.movie.fixture:1", app).waitForExistence(timeout: 5))
        element("browse.result.movie.fixture:1", app).tap()
        XCTAssertTrue(element("media.details", app).waitForExistence(timeout: 5))
        let related = element("browse.result.movie.fixture:2", app)
        for _ in 0..<12 {
            if related.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(related.isHittable)
        XCTAssertFalse(element("browse.result.movie.fixture:1", app).exists)
        related.tap()
        XCTAssertTrue(element("media.details", app).waitForExistence(timeout: 5))
    }

    private func launch(_ scenario: String = "complete") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-search", "--detail-fixture=" + scenario]
        app.launch()
        app.tabBars.buttons["Search"].tap()
        return app
    }
    private func element(_ identifier: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func choose(_ category: String, app: XCUIApplication) {
        element("browse.categories", app).tap()
        app.buttons[category].tap()
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
