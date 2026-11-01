import XCTest

final class LibraryOrganizationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testCombinedFiltersAndDiacriticInsensitiveLocalSearch() {
        let app = launch()
        search("cafe", in: app)
        let favorite = app.switches["library.favoritesFilter"]
        reveal(favorite, in: app); favorite.tap()
        app.segmentedControls["library.mediaFilter"].buttons["Movies"].tap()
        choose("Watched", picker: "library.statusFilter", in: app)
        let movie = app.buttons["library.row.movie.fixture:library:0"]
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["library.row.tvShow.fixture:library:1"].exists)
        XCTAssertTrue(movie.label.contains("Café Society"))
        XCTAssertTrue(movie.label.contains("Favorite"))
        reveal(movie, in: app)
        screenshot("Library — combined filters fixture", app: app)
    }

    @MainActor
    func testLocalSearchClearAndSortMenu() {
        let app = launch()
        search("cafe", in: app)
        choose("Release Year", picker: "library.sort", in: app)
        let tv = app.buttons["library.row.tvShow.fixture:library:1"]
        XCTAssertTrue(tv.waitForExistence(timeout: 5))
        XCTAssertTrue(tv.label.contains("2024"))
        choose("Personal Rating", picker: "library.sort", in: app)
        let movie = app.buttons["library.row.movie.fixture:library:0"]
        XCTAssertTrue(movie.label.contains("4.5 stars"))
        let field = app.searchFields["Search saved titles"]
        reveal(field, in: app); field.tap(); field.buttons["Clear text"].tap()
        let count = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "250 of 250")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        screenshot("Library — rating sort fixture", app: app)
    }

    @MainActor
    func testStatusEditRefreshesActiveFilteredView() {
        let app = launch()
        search("cafe", in: app)
        app.segmentedControls["library.mediaFilter"].buttons["Movies"].tap()
        choose("Watched", picker: "library.statusFilter", in: app)
        let movie = app.buttons["library.row.movie.fixture:library:0"]
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
        reveal(movie, in: app); movie.tap()
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        let watchlist = app.buttons["library.watchlistAction"]
        reveal(watchlist, in: app); watchlist.tap()
        app.navigationBars["Details"].buttons.element(boundBy: 0).tap()
        let empty = app.descendants(matching: .any).matching(identifier: "library.noMatches").firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        choose("Watchlist", picker: "library.statusFilter", in: app)
        XCTAssertTrue(movie.waitForExistence(timeout: 5))
    }

    @MainActor
    func testNoLocalMatchesCanNavigateToSearch() {
        let app = launch()
        search("a title not in this library", in: app)
        let noMatches = app.descendants(matching: .any).matching(identifier: "library.noMatches").firstMatch
        XCTAssertTrue(noMatches.waitForExistence(timeout: 5))
        screenshot("Library — no local matches fixture", app: app)
        let find = app.buttons["library.findTitles"]
        reveal(find, in: app); find.tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRemovingFavoriteUpdatesFilterAndPersists() {
        let store = "--ui-testing-library-store=" + UUID().uuidString
        let app = launch(extra: [store])
        search("cafe", in: app)
        let favorites = app.switches["library.favoritesFilter"]
        reveal(favorites, in: app); favorites.tap()
        app.segmentedControls["library.mediaFilter"].buttons["Movies"].tap()
        let movie = app.buttons["library.row.movie.fixture:library:0"]
        reveal(movie, in: app); movie.press(forDuration: 1)
        app.buttons["Remove Favorite"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "library.noMatches").firstMatch.waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap()
        search("cafe", in: app)
        let reloaded = app.switches["library.favoritesFilter"]
        reveal(reloaded, in: app); reloaded.tap()
        app.segmentedControls["library.mediaFilter"].buttons["Movies"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "library.noMatches").firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "--ui-testing-library-organization", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func search(_ query: String, in app: XCUIApplication) {
        let field = app.searchFields["Search saved titles"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(query)
    }

    @MainActor
    private func choose(_ label: String, picker id: String, in app: XCUIApplication) {
        let picker = app.buttons[id]
        reveal(picker, in: app); picker.tap()
        let option = app.buttons[label]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
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

    @MainActor
    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
