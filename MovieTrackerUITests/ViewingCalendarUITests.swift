import XCTest

final class ViewingCalendarUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testMonthNavigationSameDayEventsDetailsBackAndTabState() {
        let app = launch(); calendar(app)
        let heading = app.staticTexts["calendar.month"]
        let original = heading.label
        tap(app.buttons["calendar.next"], app); XCTAssertNotEqual(heading.label, original)
        tap(app.buttons["calendar.previous"], app); XCTAssertEqual(heading.label, original)
        tap(app.buttons["calendar.day.1"], app)
        let rows = app.buttons.matching(identifier: "diary.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5)); expectCount(2, app)
        tap(rows.firstMatch, app); XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        app.navigationBars["Details"].buttons.element(boundBy: 0).tap()
        expectCount(2, app)
        app.tabBars.buttons["Profile"].tap(); app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Viewing History"].exists); expectCount(2, app)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Viewing calendar — selected day, separate events"
        screenshot.lifetime = .keepAlways; add(screenshot)
    }
    @MainActor func testUndatedListSwitchAndDeletionAffectsOneEventOnly() {
        let app = launch(); calendar(app)
        tap(app.buttons["calendar.day.1"], app)
        let rows = app.buttons.matching(identifier: "diary.row")
        expectCount(2, app)
        tap(app.buttons.matching(identifier: "diary.delete").firstMatch, app)
        XCTAssertTrue(app.sheets.buttons["Delete Viewing"].waitForExistence(timeout: 5)); app.sheets.buttons["Delete Viewing"].tap()
        expectCount(1, app)
        tap(app.buttons["calendar.undated"], app)
        XCTAssertEqual(app.switches["history.undatedOnly"].value as? String, "1")
        expectCount(1, app); XCTAssertTrue(rows.firstMatch.label.contains("Date recorded"))
        tap(app.switches["history.undatedOnly"], app)
        expectCount(3, app)
    }
    @MainActor func testLargestTextDarkCalendarHasReachableDaysAndMovieNavigation() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"])
        calendar(app)
        let day = app.buttons["calendar.day.2"]; tap(day, app)
        let row = app.buttons["diary.row"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); XCTAssertTrue(row.label.contains("Movie"))
        tap(row, app); XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        app.navigationBars["Details"].buttons.element(boundBy: 0).tap()
        let edit = app.buttons["diary.edit"]; reveal(edit, app)
        XCTAssertGreaterThanOrEqual(edit.frame.height, 44)
        XCTAssertLessThanOrEqual(edit.frame.maxY, app.tabBars.firstMatch.frame.minY)
    }
    @MainActor func testOfflineRelaunchRetainsCalendarDataAndUndatedEntries() {
        let app = launch(extra: ["--ui-testing-library-store=" + UUID().uuidString]); calendar(app)
        app.terminate(); app.launchArguments.removeAll { $0 == "--ui-testing-viewing-calendar" }; app.launchArguments += ["--detail-fixture=error"]
        app.launch(); openHistory(app); calendar(app)
        tap(app.buttons["calendar.day.2"], app)
        expectCount(1, app)
        tap(app.buttons["calendar.undated"], app)
        expectCount(1, app)
    }
    @MainActor private func expectCount(_ count: Int, _ app: XCUIApplication) {
        let rows = app.buttons.matching(identifier: "diary.row")
        expectation(for: NSPredicate(format: "count == %d", count), evaluatedWith: rows)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(rows.count, count)
    }
    @MainActor private func calendar(_ app: XCUIApplication) {
        if app.segmentedControls["history.display"].exists { tap(app.segmentedControls["history.display"].buttons["Calendar"], app) }
        else { tap(app.buttons["history.display"], app); app.buttons["Calendar"].tap() }
        XCTAssertTrue(app.staticTexts["calendar.month"].waitForExistence(timeout: 5))
    }
    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "--ui-testing-viewing-calendar", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch(); openHistory(app); return app
    }
    @MainActor private func openHistory(_ app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Your screen"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap(); tap(app.buttons["library.more"], app); app.buttons["Viewing History"].tap()
        XCTAssertTrue(app.navigationBars["Viewing History"].waitForExistence(timeout: 5))
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<40 {
            if element.isHittable { return }
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable)
    }
    @MainActor private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        reveal(element, app)
        if !element.isEnabled {
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: element)
            waitForExpectations(timeout: 5)
        }
        element.tap()
    }
}
