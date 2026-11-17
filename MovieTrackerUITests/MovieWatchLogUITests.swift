import XCTest

final class MovieWatchLogUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testRatingReviewSaveAndRepeatCreateTwoEventsAndOneReview() {
        let app = details()
        tap(app.buttons["watch.open"], app)
        tap(app.buttons["rating.picker"], app); app.buttons["4.0 stars"].tap()
        XCTAssertFalse(app.staticTexts["rating.saved"].exists) // Draft selection is not a persisted save.
        tap(app.switches["watch.addReview"], app)
        let review = app.textViews["watch.review"]; tap(review, app); review.typeText("One private viewing review")
        app.buttons["watch.keyboardDone"].tap(); app.buttons["watch.save"].tap()
        XCTAssertTrue(app.buttons["watch.open"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["watch.open"].label, "Log Again")
        XCTAssertEqual(app.staticTexts["library.currentStatus"].label, "Watched")
        tap(app.buttons["watch.open"], app)
        XCTAssertFalse(app.textViews["watch.review"].exists)
        XCTAssertEqual(app.staticTexts["rating.value"].label, "4.0 stars")
        app.buttons["watch.save"].tap()
        app.tabBars.buttons["Library"].tap(); tap(app.buttons["library.more"], app); app.buttons["Viewing History"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "diary.row").count, 2)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Two movie watches — one overall rating"
        attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testPristineAndEditedCancelDoNotPersistDraftRatingOrReview() {
        let app = details()
        tap(app.buttons["watch.open"], app); app.buttons["watch.cancel"].tap()
        XCTAssertFalse(app.navigationBars["Log a Watch"].exists)
        tap(app.buttons["watch.open"], app)
        tap(app.buttons["rating.picker"], app); app.buttons["3.0 stars"].tap()
        app.buttons["watch.cancel"].tap()
        XCTAssertTrue(app.buttons["Keep Editing"].waitForExistence(timeout: 5)); app.buttons["Keep Editing"].tap()
        XCTAssertEqual(app.staticTexts["rating.value"].label, "3.0 stars")
        app.buttons["watch.cancel"].tap(); app.buttons["Discard Changes"].tap()
        XCTAssertEqual(app.staticTexts["library.currentStatus"].label, "Not in your library")
        tap(app.buttons["watch.open"], app)
        XCTAssertEqual(app.staticTexts["rating.value"].label, "Unrated")
        app.buttons["watch.cancel"].tap()
    }
    @MainActor func testUndatedLoggingAtLargestTextAndKeyboardSafeReview() {
        let app = details(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"])
        tap(app.buttons["watch.open"], app)
        tap(app.switches["watch.dateKnown"], app)
        tap(app.switches["watch.addReview"], app)
        let review = app.textViews["watch.review"]; tap(review, app); review.typeText("Accessible review")
        XCTAssertTrue(app.buttons["watch.save"].isHittable)
        XCTAssertTrue(app.buttons["watch.cancel"].isHittable)
        app.buttons["watch.keyboardDone"].tap(); app.buttons["watch.save"].tap()
        app.tabBars.buttons["Library"].tap(); tap(app.buttons["library.more"], app); app.buttons["Viewing History"].tap()
        XCTAssertTrue(app.buttons["diary.row"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["diary.row"].label.contains("Date recorded"))
    }
    @MainActor func testSavedMovieCanLogAgainAfterOfflineRelaunch() {
        let app = details(extra: ["--ui-testing-library-store=" + UUID().uuidString])
        tap(app.buttons["watch.open"], app); app.buttons["watch.save"].tap()
        app.terminate(); app.launchArguments += ["--detail-fixture=error"]; app.launch()
        XCTAssertTrue(app.navigationBars["Your screen"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap(); tap(app.buttons["library.row.movie.fixture:1"], app)
        tap(app.buttons["watch.open"], app); app.buttons["watch.save"].tap()
        app.navigationBars["Details"].buttons.element(boundBy: 0).tap()
        tap(app.buttons["library.more"], app); app.buttons["Viewing History"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "diary.row").count, 2)
    }
    @MainActor private func details(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch(); XCTAssertTrue(app.navigationBars["Your screen"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Search"].tap()
        let search = app.searchFields["Movies and TV shows"]; XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("sample")
        tap(app.buttons["search.result.movie.fixture:1"], app)
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        return app
    }
    @MainActor private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<30 {
            if element.isHittable { break }
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5)); XCTAssertTrue(element.isHittable); element.tap()
    }
}
