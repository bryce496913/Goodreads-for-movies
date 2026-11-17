import XCTest

@MainActor
final class PersonalStatisticsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testProfileNavigationYearSelectionAndUniqueWatchCounts() throws {
        let app = try launch(populated: true)
        let year = find("statistics.year", app)
        year.tap(); app.buttons["2024"].tap()
        let movies = find("statistics.movies", app)
        XCTAssertTrue(movies.waitForExistence(timeout: 5))
        XCTAssertTrue(movies.label.contains("2"))
        XCTAssertTrue(find("statistics.uniqueMovies", app).label.contains("1"))
        let chart = find("statistics.monthlyChart", app)
        reveal(chart, app); XCTAssertTrue(chart.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "041 Year in Review — diary activity"; attachment.lifetime = .keepAlways
        add(attachment)
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        reveal(year, app, up: false)
        year.tap(); app.buttons["2025"].tap()
        XCTAssertTrue(find("statistics.movies", app).waitForExistence(timeout: 5))
        XCTAssertTrue(find("statistics.movies", app).label.contains("1"))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(find("screen.profile", app).waitForExistence(timeout: 5))
    }
    func testEmptyAndAccessibleChartTextFallback() throws {
        let app = try launch(populated: false)
        XCTAssertTrue(find("statistics.empty", app).waitForExistence(timeout: 5))
        let monthly = find("statistics.month.1", app)
        reveal(monthly, app); XCTAssertTrue(monthly.label.contains("0 movie"))
        let ratings = find("statistics.ratingsChart", app)
        reveal(ratings, app); XCTAssertTrue(ratings.exists)
        let unrated = find("statistics.unrated", app)
        reveal(unrated, app); XCTAssertTrue(unrated.label.contains("0"))
    }
    func testMissingGenresAndEpisodeUnknownDatesAreExplained() throws {
        let app = try launch(populated: true)
        let genreEmpty = find("statistics.genres.empty", app)
        reveal(genreEmpty, app); XCTAssertTrue(genreEmpty.exists)
        let episodes = find("statistics.overallEpisodes", app)
        reveal(episodes, app); XCTAssertTrue(episodes.label.contains("2"))
        let note = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Marking time records an action")).firstMatch
        reveal(note, app); XCTAssertTrue(note.exists)
    }

    private func launch(populated: Bool) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "--ui-testing-dashboard"]
        if populated { app.launchEnvironment["DASHBOARD_UI_INPUT"] = try payload() }
        app.launch()
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(find("profile.yearInReview", app).waitForExistence(timeout: 5))
        find("profile.yearInReview", app).tap()
        XCTAssertTrue(find("screen.statistics", app).waitForExistence(timeout: 5))
        return app
    }
    private func find(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, up: Bool = true) {
        for _ in 0..<30 {
            if element.isHittable { return }
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }
    /// Test-owned fixture uses existing DEBUG in-memory import, never the personal store.
    private func payload() throws -> String {
        func stamp(_ iso: String) -> TimeInterval { ISO8601DateFormatter().date(from: iso)!.timeIntervalSinceReferenceDate }
        let movie: [String: Any] = ["kind": "movie", "value": "fixture:stats"]
        let show: [String: Any] = ["kind": "tvShow", "value": "fixture:stats"]
        let recorded = stamp("2025-01-01T00:00:00Z")
        let rows: [[String: Any]] = ["2024-02-29T00:00:00Z", "2024-12-31T00:00:00Z", "2025-01-01T00:00:00Z"].enumerated().map { index, iso in
            ["id": "00000000-0000-0000-0000-00000000000\(index + 1)", "mediaID": movie,
             "title": "Local Movie", "watchedDate": stamp(iso), "recordedAt": recorded]
        }
        func progress(_ index: Int, date: TimeInterval?) throws -> [String: Any] {
            let episodeID: [String: Any] = ["seriesID": show, "providerValue": "fixture:episode:\(index)"]
            let data = try JSONSerialization.data(withJSONObject: ["id": episodeID, "seasonNumber": 1, "number": index, "title": "Episode", "overview": ""])
            var row: [String: Any] = ["id": "00000000-0000-0000-0000-00000000001\(index)",
                                     "episodeID": episodeID, "season": 1, "watched": true, "episodeData": data.base64EncodedString()]
            if let date { row["watchedAt"] = date }
            return row
        }
        let object: [String: Any] = ["titles": [], "viewings": rows, "reviews": [], "seasons": [],
                                   "progress": try [progress(1, date: recorded), progress(2, date: nil)]]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}
