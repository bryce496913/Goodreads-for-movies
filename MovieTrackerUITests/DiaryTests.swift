import XCTest

final class DiaryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testReviewCreationEditingAndCancelWithoutSaving() {
        let app = openDetails()
        write("First private review", in: app)
        openArchive(in: app)
        XCTAssertTrue(app.staticTexts["review.text"].waitForExistence(timeout: 5))
        tap(app.buttons.matching(identifier: "review.edit").firstMatch, in: app)
        replaceEditorText("Unsaved replacement", in: app)
        app.buttons["review.cancel"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "review.text").firstMatch.label, "First private review")
        tap(app.buttons.matching(identifier: "review.edit").firstMatch, in: app)
        replaceEditorText("Edited private review", in: app)
        app.buttons["review.save"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "review.text").firstMatch.label, "Edited private review")
    }

    @MainActor
    func testDeleteReviewAfterConfirmation() {
        let app = openDetails()
        write("Review to remove", in: app)
        openArchive(in: app)
        tap(app.buttons.matching(identifier: "review.delete").firstMatch, in: app)
        let confirmation = app.sheets.buttons["Delete Review"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(app.staticTexts["No personal reviews"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMultipleViewingEventsAndDeletionOfOne() {
        let app = openDetails(kind: "tvShow")
        for _ in 0..<2 {
            tap(app.buttons["diary.record"], in: app)
            XCTAssertTrue(app.buttons["diary.save"].waitForExistence(timeout: 5))
            app.buttons["diary.save"].tap()
        }
        app.tabBars.buttons["Library"].tap()
        app.buttons["library.more"].tap()
        tap(app.buttons["Viewing History"], in: app)
        XCTAssertTrue(app.navigationBars["Viewing History"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "diary.row").count, 2)
        tap(app.buttons.matching(identifier: "diary.delete").firstMatch, in: app)
        let confirmation = app.sheets.buttons["Delete Viewing"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "diary.row").count, 1)
    }

    @MainActor
    func testOfflineReviewArchiveAfterProcessRelaunch() {
        let app = openDetails(extra: ["--ui-testing-library-store=" + UUID().uuidString])
        write("Private text survives relaunch", in: app)
        app.terminate()
        app.launchArguments += ["--detail-fixture=error"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        openArchive(in: app)
        XCTAssertTrue(app.staticTexts["review.text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "review.text").firstMatch.label, "Private text survives relaunch")
        tap(app.buttons.matching(identifier: "review.edit").firstMatch, in: app)
        XCTAssertEqual(app.textViews["review.editor"].value as? String, "Private text survives relaunch")
    }

    @MainActor
    private func openDetails(kind: String = "movie", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Search"].tap()
        let field = app.searchFields["Movies and TV shows"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("sample")
        let row = app.buttons["search.result." + kind + ".fixture:1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        tap(row, in: app)
        XCTAssertTrue(app.staticTexts["details.title"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func write(_ text: String, in app: XCUIApplication) {
        tap(app.buttons["review.write"], in: app)
        let editor = app.textViews["review.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.save"].isEnabled)
        editor.tap(); editor.typeText(text)
        app.buttons["review.save"].tap()
        XCTAssertTrue(app.buttons["review.write"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func replaceEditorText(_ text: String, in app: XCUIApplication) {
        let editor = app.textViews["review.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let original = editor.value as? String ?? ""
        editor.tap()
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + text)
    }

    @MainActor
    private func openArchive(in app: XCUIApplication) {
        app.tabBars.buttons["Library"].tap()
        app.buttons["library.more"].tap()
        tap(app.buttons["Personal Reviews"], in: app)
        XCTAssertTrue(app.navigationBars["Personal Reviews"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<60 {
            if element.isHittable { break }
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }
}
