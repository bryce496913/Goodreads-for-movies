import XCTest

@MainActor
final class MetadataRecoveryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testSparseDetailsExposeRefreshWithoutInventingMissingInformation() {
        let app = launch("missing")
        let missing = app.staticTexts["details.incomplete"]
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        XCTAssertTrue(missing.label.contains("synopsis")); XCTAssertTrue(missing.label.contains("runtime"))
        let refresh = app.buttons["details.retry"]
        reveal(refresh, app); refresh.tap()
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["details.title"].label, "Sample Story")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "042 Missing metadata and explicit recovery"; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testFailedRefreshKeepsLoadedTitleAndShowsOneRecoveryError() {
        let app = launch("offline-after-load")
        let title = app.staticTexts["details.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let refresh = app.buttons["details.retry"]
        reveal(refresh, app); refresh.tap()
        let error = app.staticTexts["details.cached"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("Showing saved information"))
        XCTAssertEqual(title.label, "Sample Story")
        XCTAssertFalse(app.staticTexts["details.saveError"].exists)
    }
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "--detail-fixture=" + scenario]
        app.launch(); app.tabBars.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("sample")
        let result = app.buttons["search.result.movie.fixture:1"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        return app
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<15 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
}
