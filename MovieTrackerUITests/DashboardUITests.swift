import XCTest

/// All dataset values are owned by the test target; app import is DEBUG + isolated in-memory only.
final class DashboardUITests: XCTestCase {
    @MainActor private func launch(populated: Bool) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "--ui-testing-dashboard"]
        if populated { app.launchEnvironment["DASHBOARD_UI_INPUT"] = try DashboardUIFixture.payload() }
        app.launch()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor func testEmptyHomeRoutesToSearchAndProfileAverageUnavailable() throws {
        let app = try launch(populated: false)
        XCTAssertTrue(app.buttons["home.findTitles"].waitForExistence(timeout: 10))
        screenshot(app, "Home-empty")
        app.buttons["home.findTitles"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Profile"].tap()
        assertMetric(app, "movies", "0")
        let average = find(app, "profile.average")
        reveal(average, app)
        XCTAssertTrue(average.label.contains("Unavailable"))
        screenshot(app, "Profile-empty")
    }
    @MainActor func testPopulatedProfileMatchesDeterministicFixture() throws {
        let app = try launch(populated: true)
        XCTAssertTrue(app.buttons["home.nextEpisode"].waitForExistence(timeout: 10))
        screenshot(app, "Home-populated")
        app.tabBars.buttons["Profile"].tap()
        assertMetric(app, "movies", "1"); assertMetric(app, "series", "1")
        assertMetric(app, "episodes", "1"); assertMetric(app, "watchlist", "1")
        assertMetric(app, "favorites", "2"); assertMetric(app, "ratings", "2")
        let average = find(app, "profile.average"); reveal(average, app)
        XCTAssertTrue(average.label.contains("3.5"))
        assertMetric(app, "reviews", "1"); assertMetric(app, "events", "2")
        screenshot(app, "Profile-populated")
    }
    @MainActor func testHomeEpisodeAndHistoryNavigationAndLibraryShortcut() throws {
        let app = try launch(populated: true)
        let next = app.buttons["home.nextEpisode"]
        XCTAssertTrue(next.waitForExistence(timeout: 10)); next.tap()
        XCTAssertTrue(app.navigationBars["Season 1"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let history = app.buttons["home.history"]; reveal(history, app); history.tap()
        XCTAssertTrue(app.navigationBars["Viewing History"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let library = app.buttons["home.openLibrary"]; reveal(library, app); library.tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved titles — 3 of 3"].waitForExistence(timeout: 5))
    }
    @MainActor func testEpisodeMutationUpdatesProfileAcrossTabs() throws {
        let app = try launch(populated: true)
        let next = app.buttons["home.nextEpisode"]
        XCTAssertTrue(next.waitForExistence(timeout: 10)); next.tap()
        let toggle = app.switches["episode.toggle.fixture:episode:2"]
        reveal(toggle, app); toggle.tap()
        app.tabBars.buttons["Profile"].tap()
        let metric = find(app, "profile.stat.episodes")
        reveal(metric, app)
        let updated = NSPredicate(format: "label CONTAINS %@", "2")
        expectation(for: updated, evaluatedWith: metric)
        waitForExpectations(timeout: 5)
    }
    @MainActor private func find(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }
    @MainActor private func assertMetric(_ app: XCUIApplication, _ id: String, _ count: String) {
        let metric = find(app, "profile.stat." + id); reveal(metric, app)
        XCTAssertTrue(metric.exists); XCTAssertTrue(metric.label.hasSuffix(count), metric.label)
    }
    @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}

private enum DashboardUIFixture {
    static func payload() throws -> String {
        let date = Date(timeIntervalSince1970: 1_735_689_600).timeIntervalSinceReferenceDate
        let aired = Date(timeIntervalSince1970: 1_577_836_800).timeIntervalSinceReferenceDate
        func uuid(_ number: Int) -> String { String(format: "00000000-0000-0000-0000-%012d", number) }
        func id(_ value: String, _ kind: String = "movie") -> [String: String] { ["kind": kind, "value": "fixture:" + value] }
        func data(_ object: Any) throws -> String { try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).base64EncodedString() }
        func title(_ number: Int, _ name: String, _ kind: String, _ status: String, _ favorite: Bool, _ rating: Int?) -> [String: Any] {
            var row: [String: Any] = ["recordID": uuid(number), "mediaID": id(String(number), kind), "title": name,
                "status": status, "favorite": favorite, "addedAt": date, "updatedAt": date]
            if let rating { row["ratingUnits"] = rating; row["ratingUpdatedAt"] = date }
            return row
        }
        let seriesID = id("3", "tvShow")
        func episode(_ number: Int) -> [String: Any] {
            ["id": ["seriesID": seriesID, "providerValue": "fixture:episode:\(number)"], "seasonNumber": 1,
             "number": number, "title": "Fixture episode \(number)", "airDate": aired, "overview": "Saved offline episode"]
        }
        let episodes = [episode(1), episode(2)]
        let input: [String: Any] = [
            "titles": [title(1, "Fixture Movie", "movie", "watched", true, 8),
                       title(2, "A long saved Watchlist title for accessibility and wrapping", "movie", "watchlist", false, nil),
                       title(3, "Fixture Series", "tvShow", "watching", true, 6)],
            "viewings": (0..<2).map { ["id": uuid(10 + $0), "mediaID": id("1"), "title": "Fixture Movie",
                                      "watchedDate": aired + Double($0) * 86_400, "recordedAt": date] as [String: Any] },
            "reviews": [["id": uuid(20), "mediaID": id("1"), "title": "Fixture Movie", "text": "Private fixture review",
                         "createdAt": date, "editedAt": date, "imported": false]],
            "progress": [["id": uuid(30), "episodeID": episode(1)["id"]!, "season": 1,
                          "watched": true, "watchedAt": date, "episodeData": try data(episode(1))]],
            "seasons": [["id": uuid(40), "seriesID": seriesID, "title": "Fixture Series", "number": 1,
                         "expectedEpisodes": 2, "expectedRegularSeasons": 1, "listed": true, "loaded": true,
                         "episodesData": try data(episodes), "listedIDsData": try data(episodes.map { $0["id"]! }), "refreshedAt": date]]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        return String(decoding: encoded, as: UTF8.self)
    }
}
