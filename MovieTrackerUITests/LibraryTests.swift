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
        tap(row.identifier, in: app)
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
        XCTAssertTrue(app.navigationBars["Your screen"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap()
        let row = app.buttons["library.row.movie.fixture:1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Sample Story"))
        tap(row.identifier, in: app)
        XCTAssertTrue(app.staticTexts["details.cached"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["details.title"].exists)
    }

    @MainActor
    func testAllStatusTransitionsPreserveFavoriteAndHalfStarRating() {
        let app = openDetails(kind: "tvShow")
        tap("library.favoriteAction", in: app)
        tap("rating.picker", in: app)
        app.buttons["2.5 stars"].tap()
        let choices = ["library.watchlistAction", "library.watchingAction", "library.watchedAction", "library.clearStatus"]
        let labels = ["Watchlist", "Watching", "Watched", "No viewing status"]
        for from in 0..<choices.count {
            for to in 0..<choices.count {
                if from < 3 || app.buttons["library.statusSelector"].value as? String != "No viewing status" {
                    tap(choices[from], in: app)
                }
                if to < 3 || from < 3 { tap(choices[to], in: app) }
                XCTAssertEqual(app.staticTexts["library.currentStatus"].label, labels[to])
                XCTAssertEqual(app.buttons["library.favoriteAction"].value as? String, "Selected")
                XCTAssertEqual(app.staticTexts["rating.value"].label, "2.5 stars")
            }
        }
        app.tabBars.buttons["Library"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "library.row.tvShow.fixture:1").count, 1)
    }

    @MainActor
    func testMovieStatusSelectorOmitsWatchingAndRemovalStaysBelowRoutineActions() {
        let app = openDetails(kind: "movie", extraArguments: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"
        ])
        tap("library.statusSelector", in: app)
        XCTAssertFalse(app.buttons["library.watchingAction"].exists)
        app.buttons["library.watchlistAction"].tap()
        let remove = app.buttons["library.removeAction"]
        for _ in 0..<30 {
            if remove.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(remove.isHittable)
        XCTAssertLessThanOrEqual(remove.frame.maxY, app.tabBars.firstMatch.frame.minY)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Personal controls — largest text dark"
        attachment.lifetime = .keepAlways
        add(attachment)
        tap(remove.identifier, in: app)
        let cancel = app.sheets.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertEqual(app.staticTexts["library.currentStatus"].label, "Watchlist")
        XCTAssertTrue(app.buttons["library.statusSelector"].exists)
    }

    @MainActor
    private func openDetails(kind: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search"] + extraArguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Your screen"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields["Movies and TV shows"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("sample")
        let row = app.buttons["search.result." + kind + ".fixture:1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        tap(row.identifier, in: app)
        XCTAssertTrue(app.staticTexts["details.title"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func tap(_ id: String, in app: XCUIApplication) {
        if ["library.watchlistAction", "library.watchingAction", "library.watchedAction", "library.clearStatus"].contains(id) {
            tap("library.statusSelector", in: app)
        }
        let button = app.buttons[id]
        for _ in 0..<30 {
            if button.isHittable { break }
            if button.exists && button.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }
}
