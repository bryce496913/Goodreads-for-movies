import XCTest

final class V07JourneyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testDatedAndUndatedFastLogsAgreeAcrossProfileCalendarAndList() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields["Movies and TV shows"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("sample")
        tap(app.buttons["search.result.movie.fixture:1"], app)
        tap(app.buttons["watch.open"], app)
        tap(app.buttons["rating.picker"], app); app.buttons["4.0 stars"].tap()
        app.buttons["watch.save"].tap()
        tap(app.buttons["watch.open"], app)
        tap(app.switches["watch.dateKnown"], app)
        app.buttons["watch.save"].tap()
        XCTAssertTrue(app.buttons["watch.open"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Profile"].tap()
        tap(find("profile.yearInReview", app), app)
        let movieCount = find("statistics.movies", app)
        XCTAssertTrue(movieCount.waitForExistence(timeout: 5))
        XCTAssertTrue(movieCount.label.contains("1"))
        XCTAssertTrue(find("statistics.uniqueMovies", app).label.contains("1"))
        app.tabBars.buttons["Library"].tap()
        tap(app.buttons["library.more"], app); app.buttons["Viewing History"].tap()
        let rows = app.buttons.matching(identifier: "diary.row")
        XCTAssertEqual(rows.count, 2)
        app.segmentedControls["history.display"].buttons["Calendar"].tap()
        let undated = app.buttons["calendar.undated"]
        XCTAssertTrue(undated.waitForExistence(timeout: 5)); XCTAssertTrue(undated.label.contains("1"))
        XCTAssertEqual(rows.count, 1)
        tap(undated, app)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1); XCTAssertTrue(rows.firstMatch.label.contains("Date recorded"))
    }
    @MainActor private func find(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<30 {
            if element.isHittable { break }
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable); element.tap()
    }
}
