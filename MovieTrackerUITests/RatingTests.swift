import XCTest

final class RatingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testSetEditClearAndLibraryConsistency() {
        let app = openDetails()
        select("4.5 stars", in: app)
        XCTAssertEqual(app.staticTexts["rating.value"].label, "4.5 stars")
        XCTAssertEqual(app.staticTexts["library.currentStatus"].label, "No viewing status")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Personal rating — fixture 4.5 stars"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        select("2.5 stars", in: app)
        XCTAssertEqual(app.staticTexts["rating.value"].label, "2.5 stars")
        app.tabBars.buttons["Library"].tap()
        let row = app.buttons["library.row.movie.fixture:1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("2.5 stars"))
        row.tap()
        let clear = app.buttons["rating.clear"]
        reveal(clear, in: app)
        clear.tap()
        XCTAssertEqual(app.staticTexts["rating.value"].label, "Unrated")
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(row.label.contains("Unrated"))
    }

    @MainActor
    func testAccessibleStepperAndStatusIndependence() {
        let app = openDetails(kind: "tvShow")
        let stepper = app.steppers["rating.stepper"]
        reveal(stepper, in: app)
        stepper.buttons["Increment"].tap()
        XCTAssertEqual(app.staticTexts["rating.value"].label, "0.5 stars")
        let watched = app.buttons["library.watchedAction"]
        reveal(watched, in: app)
        watched.tap()
        XCTAssertEqual(app.staticTexts["library.currentStatus"].label, "Watched")
        let clear = app.buttons["rating.clear"]
        reveal(clear, in: app)
        clear.tap()
        XCTAssertEqual(app.staticTexts["library.currentStatus"].label, "Watched")
        XCTAssertEqual(app.staticTexts["rating.value"].label, "Unrated")
    }

    @MainActor
    func testRatingSurvivesProcessRelaunch() {
        let app = openDetails(extraArguments: ["--ui-testing-library-store=" + UUID().uuidString])
        select("5.0 stars", in: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Library"].tap()
        let row = app.buttons["library.row.movie.fixture:1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("5.0 stars"))
        row.tap()
        XCTAssertTrue(app.staticTexts["rating.value"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["rating.value"].label, "5.0 stars")
    }

    @MainActor
    private func openDetails(kind: String = "movie", extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extraArguments
        app.launch()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields["Movies and TV shows"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("sample")
        let row = app.buttons["search.result." + kind + ".fixture:1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        reveal(row, in: app)
        row.tap()
        XCTAssertTrue(app.staticTexts["details.title"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func select(_ stars: String, in app: XCUIApplication) {
        let picker = app.buttons["rating.picker"]
        reveal(picker, in: app)
        picker.tap()
        let option = app.buttons[stars]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<30 {
            if element.isHittable { break }
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
}
