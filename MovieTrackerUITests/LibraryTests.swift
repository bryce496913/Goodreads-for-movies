import XCTest

final class LibraryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSaveAndStatusChangesUpdateLibraryImmediately() {
        let app = openDetails(kind: "tvShow")
        tap("library.watchlistAction", in: app)
        XCTAssertEqual(app.staticTexts["library.currentStatus"].label, "Watchlist")
        tap("library.favoriteAction", in: app)
        tap("library.watchingAction", in: app)
        XCTAssertEqual(app.staticTexts["library.currentStatus"].label, "Watching")
        tap("library.watchedAction", in: app)
        XCTAssertEqual(app.staticTexts["library.currentStatus"].label, "Watched")
        app.tabBars.buttons["Library"].tap()
        let row = app.buttons["library.row.tvShow.fixture:1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Watched"))
        XCTAssertTrue(row.label.contains("Favorite"))
        row.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRemoveFromLibraryRestoresEmptyState() {
        let app = openDetails(kind: "movie")
        tap("library.watchlistAction", in: app)
        tap("library.removeAction", in: app)
        let confirmation = app.sheets.buttons["Remove from Library"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "library.empty").firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testPersistentRelaunchAndOfflineSavedDetails() {
        let storeArgument = "--ui-testing-library-store=" + UUID().uuidString
        let app = openDetails(kind: "movie", extraArguments: [storeArgument])
        tap("library.watchlistAction", in: app)
        app.terminate()
        app.launchArguments += ["--detail-fixture=error"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap()
        let row = app.buttons["library.row.movie.fixture:1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Sample Story"))
        row.tap()
        XCTAssertTrue(app.staticTexts["details.cached"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["details.title"].exists)
    }

    @MainActor
    private func openDetails(kind: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search"] + extraArguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields["Movies and TV shows"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("sample")
        let row = app.buttons["search.result." + kind + ".fixture:1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["details.title"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func tap(_ id: String, in app: XCUIApplication) {
        let button = app.buttons[id]
        for _ in 0..<30 {
            if button.isHittable { break }
            if button.exists && button.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }
}
