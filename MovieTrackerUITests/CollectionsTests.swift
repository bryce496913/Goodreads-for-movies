import XCTest

final class CollectionsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testCreateRenameCancelAndDeleteCollection() {
        let app = launch()
        app.tabBars.buttons["Library"].tap()
        create("Weekend", app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "collection.row.")).firstMatch
        tap(row, app)
        XCTAssertTrue(app.navigationBars["Weekend"].waitForExistence(timeout: 5))
        tap(app.buttons["collection.actions"], app)
        tap(app.buttons["collection.rename"], app)
        replaceName("Unsaved", app)
        app.buttons["collection.cancel"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(app.navigationBars["Weekend"].exists)
        tap(app.buttons["collection.actions"], app)
        tap(app.buttons["collection.rename"], app)
        replaceName("Weekend Films", app)
        app.buttons["collection.save"].tap()
        XCTAssertTrue(app.navigationBars["Weekend Films"].waitForExistence(timeout: 5))
        tap(app.buttons["collection.actions"], app)
        tap(app.buttons["collection.delete"], app)
        let confirm = app.sheets.buttons["Delete Collection"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "collection.row.")).count, 0)
    }

    @MainActor func testMovieInTwoListsHasNoViewingStatusAndRemovalIsIsolated() {
        let app = launch()
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields["Movies and TV shows"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("sample")
        let result = app.buttons["search.result.movie.fixture:1"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); tap(result, app)
        tap(app.buttons["collection.addToList"], app)
        create("Together", app)
        let first = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "collection.select.")).firstMatch
        tap(first, app)
        create("Again", app)
        let toggles = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "collection.select."))
        XCTAssertEqual(toggles.count, 2)
        for index in 0..<toggles.count {
            let toggle = toggles.element(boundBy: index)
            if toggle.value as? String == "0" { tap(toggle, app) }
        }
        app.buttons["collection.done"].tap()
        XCTAssertEqual(app.staticTexts["library.currentStatus"].label, "No viewing status")
        app.tabBars.buttons["Library"].tap()
        let collections = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "collection.row."))
        XCTAssertEqual(collections.count, 2)
        tap(collections.firstMatch, app)
        let member = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "collection.member.")).firstMatch
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        tap(member, app)
        XCTAssertTrue(app.navigationBars["Details"].waitForExistence(timeout: 5))
        app.navigationBars["Details"].buttons.element(boundBy: 0).tap()
        member.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["This collection is empty"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.row.movie.fixture:1"].exists)
        let other = collections.element(boundBy: 1)
        tap(other, app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "collection.member.")).firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Collection — offline local membership fixture"
        shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Your screen"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func create(_ name: String, _ app: XCUIApplication) {
        tap(app.buttons["collection.create"], app)
        let field = app.textFields["collection.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["collection.save"].isEnabled)
        field.tap(); field.typeText(name)
        app.buttons["collection.save"].tap()
    }
    @MainActor private func replaceName(_ name: String, _ app: XCUIApplication) {
        let field = app.textFields["collection.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let existing = field.value as? String ?? ""
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + name)
    }
    @MainActor private func tap(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<35 {
            if element.isHittable { break }
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable); element.tap()
    }
}
