import XCTest

final class AppShellUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testFourNativeTabsKeepSelectionRootIdentityAndTouchTargets() {
        let app = launch()
        let roots = [("Home", "screen.home"), ("Search", "screen.search"), ("Library", "screen.library"), ("Profile", "screen.profile")]
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        for (title, identity) in roots {
            select(title, in: app)
            assertScreen(title, in: app)
            XCTAssertTrue(find(identity, in: app).exists)
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.isSelected); XCTAssertTrue(tab.isHittable)
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
            XCTAssertEqual(app.navigationBars.count, 1)
            XCTAssertEqual(app.tabBars.count, 1)
        }
        screenshot("Shell — four native tabs", app)
    }

    @MainActor func testSearchAndProfileStacksSurviveTabRoundTripsAndBack() {
        let app = launch()
        openDetails(in: app)
        select("Profile", in: app)
        tap(app.buttons["profile.settings"], in: app)
        assertScreen("Settings", in: app)
        select("Search", in: app)
        assertScreen("Details", in: app)
        back(from: "Details", to: "Search", in: app)
        XCTAssertEqual(app.searchFields["Movies and TV shows"].value as? String, "sample")
        XCTAssertTrue(app.buttons["search.result.movie.fixture:1"].exists)
        select("Profile", in: app)
        assertScreen("Settings", in: app)
        back(from: "Settings", to: "Profile", in: app)
        XCTAssertEqual(app.navigationBars.count, 1)
    }

    @MainActor func testLibrarySubpagesKeepNativePathAcrossTabChanges() {
        let app = launch()
        select("Library", in: app)
        tap(app.switches["library.favoritesFilter"], in: app)
        let localSearch = app.searchFields["Search saved titles"]
        tap(localSearch, in: app); localSearch.typeText("kept query")
        for (action, title, emptyID) in [("diary.open", "Viewing History", "history.empty"),
                                         ("review.archive", "Personal Reviews", "reviews.empty"),
                                         ("tv.savedProgress", "TV Episode Progress", "tv.empty")] {
            select("Library", in: app)
            openLibrarySection(action, in: app)
            assertScreen(title, in: app)
            XCTAssertTrue(find(emptyID, in: app).exists)
            select("Home", in: app); assertScreen("Home", in: app)
            select("Library", in: app); assertScreen(title, in: app)
            back(from: title, to: "Library", in: app)
            XCTAssertEqual(app.switches["library.favoritesFilter"].value as? String, "1")
            XCTAssertEqual(app.searchFields["Search saved titles"].value as? String, "kept query")
            XCTAssertEqual(app.navigationBars.count, 1)
        }
    }

    @MainActor func testExplicitLibraryShortcutReturnsToCollectionRoot() {
        let app = launch()
        select("Library", in: app)
        tap(app.switches["library.favoritesFilter"], in: app)
        let localSearch = app.searchFields["Search saved titles"]
        tap(localSearch, in: app); localSearch.typeText("reset query")
        openLibrarySection("diary.open", in: app)
        assertScreen("Viewing History", in: app)
        select("Home", in: app)
        tap(app.buttons["home.openLibrary"], in: app)
        assertScreen("Library", in: app)
        XCTAssertTrue(find("screen.library", in: app).exists)
        XCTAssertTrue(app.buttons["library.more"].isHittable)
        XCTAssertEqual(app.switches["library.favoritesFilter"].value as? String, "0")
        XCTAssertNotEqual(app.searchFields["Search saved titles"].value as? String, "reset query")
    }

    @MainActor func testEmptyStatesRetainDescriptionsAndDiscoveryAction() {
        let app = launch()
        XCTAssertTrue(find("home.empty", in: app).waitForExistence(timeout: 5))
        tap(app.buttons["home.findTitles"], in: app)
        assertScreen("Search", in: app)
        XCTAssertTrue(app.staticTexts["Find your next story"].exists)
        select("Library", in: app)
        XCTAssertTrue(find("library.empty", in: app).waitForExistence(timeout: 5))
        tap(app.buttons["library.findTitles"], in: app)
        assertScreen("Search", in: app)
        select("Profile", in: app)
        let emptyDiary = find("profile.emptyDiary", in: app)
        reveal(emptyDiary, in: app); XCTAssertTrue(emptyDiary.exists)
        screenshot("Shell — empty Profile diary", app)
    }

    @MainActor func testReviewKeyboardDismissalAndUnsavedChangesProtection() {
        let app = launch(); openDetails(in: app)
        tap(app.buttons["review.write"], in: app)
        let editor = app.textViews["review.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.save"].isEnabled)
        editor.tap(); editor.typeText("Unsaved shell regression draft")
        XCTAssertTrue(app.buttons["review.save"].isHittable)
        XCTAssertTrue(app.buttons["review.cancel"].isHittable)
        tap(app.buttons["review.keyboardDone"], in: app)
        assertGone(app.keyboards.firstMatch)
        XCTAssertEqual(editor.value as? String, "Unsaved shell regression draft")
        app.buttons["review.cancel"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 5))
        app.sheets.buttons["Cancel"].tap() // Keep editing; no draft loss.
        XCTAssertEqual(editor.value as? String, "Unsaved shell regression draft")
        app.buttons["review.cancel"].tap(); app.buttons["Discard Changes"].tap()
        assertGone(app.navigationBars["Personal Review"])
        select("Library", in: app); openLibrarySection("review.archive", in: app)
        XCTAssertTrue(find("reviews.empty", in: app).waitForExistence(timeout: 5))
    }

    @MainActor func testViewingSheetCancelDoesNotCreateHistory() {
        let app = launch(); openDetails(in: app)
        tap(app.buttons["diary.record"], in: app)
        XCTAssertTrue(app.buttons["diary.cancel"].waitForExistence(timeout: 5))
        app.buttons["diary.cancel"].tap() // Pristine sheet closes without a discard dialog.
        assertGone(app.navigationBars["Record Viewing"])
        tap(app.buttons["diary.record"], in: app)
        let known = app.switches["diary.dateKnown"]
        XCTAssertTrue(known.waitForExistence(timeout: 5)); known.tap()
        app.buttons["diary.cancel"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 5)); app.buttons["Discard Changes"].tap()
        assertGone(app.navigationBars["Record Viewing"])
        select("Library", in: app); openLibrarySection("diary.open", in: app)
        XCTAssertTrue(find("history.empty", in: app).waitForExistence(timeout: 5))
    }

    @MainActor func testSettingsCreditsAndBackupUseOneBackNavigationHierarchy() {
        let app = launch(); select("Profile", in: app)
        tap(app.buttons["profile.settings"], in: app); assertScreen("Settings", in: app)
        tap(app.buttons["settings.backup"], in: app); assertScreen("Export & Restore", in: app)
        XCTAssertTrue(find("screen.backup", in: app).exists)
        assertReachable(app.buttons["backup.export"], in: app)
        assertReachable(app.buttons["backup.import"], in: app) // Inspect, don't open native file providers in this deterministic suite.
        back(from: "Export & Restore", to: "Settings", in: app)
        tap(app.buttons["About & Credits"], in: app); assertScreen("About & Credits", in: app)
        back(from: "About & Credits", to: "Settings", in: app)
        back(from: "Settings", to: "Profile", in: app)
        XCTAssertEqual(app.navigationBars.count, 1)
    }

    @MainActor func testLargestDynamicTypeKeepsFiltersSettingsAndKeyboardControlsReachable() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        select("Search", in: app)
        tap(app.buttons["search.filters"], in: app); app.buttons["Movies"].tap()
        select("Library", in: app)
        assertReachable(app.buttons["library.mediaFilter"], in: app)
        assertReachable(app.switches["library.favoritesFilter"], in: app)
        select("Profile", in: app); tap(app.buttons["profile.settings"], in: app)
        let field = app.secureTextFields["settings.token"]
        tap(field, in: app); field.typeText("nonsecret-ui-fixture")
        tap(app.buttons["settings.keyboardDone"], in: app)
        assertGone(app.keyboards.firstMatch)
        assertReachable(app.buttons["settings.saveCredential"], in: app)
        screenshot("Shell — largest Dynamic Type Settings", app)
    }

    @MainActor func testRequestedDarkAppearanceRetainsNativeRootIdentity() {
        let app = launch(style: "Dark")
        for title in ["Home", "Search", "Library", "Profile"] {
            select(title, in: app); assertScreen(title, in: app)
            XCTAssertEqual(app.navigationBars.count, 1)
            XCTAssertTrue(app.tabBars.buttons[title].isSelected)
        }
        screenshot("Shell — requested dark Profile", app)
    }

    @MainActor private func launch(style: String = "Light", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-AppleInterfaceStyle", style] + extra
        app.launch(); assertScreen("Home", in: app); return app
    }
    @MainActor private func select(_ title: String, in app: XCUIApplication) { app.tabBars.buttons[title].tap() }
    @MainActor private func assertScreen(_ title: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "Missing screen: " + title)
    }
    @MainActor private func back(from: String, to: String, in app: XCUIApplication) {
        app.navigationBars[from].buttons.element(boundBy: 0).tap(); assertScreen(to, in: app)
    }
    @MainActor private func find(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<30 {
            if element.exists && element.isHittable { return }
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func assertReachable(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app); XCTAssertTrue(element.isHittable)
        XCTAssertTrue(element.isEnabled)
    }
    @MainActor private func tap(_ element: XCUIElement, in app: XCUIApplication) { reveal(element, in: app); element.tap() }
    @MainActor private func openLibrarySection(_ id: String, in app: XCUIApplication) {
        tap(app.buttons["library.more"], in: app)
        let item = app.buttons[id]; XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
    }
    @MainActor private func openDetails(in app: XCUIApplication) {
        select("Search", in: app)
        let field = app.searchFields["Movies and TV shows"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("sample")
        let row = app.buttons["search.result.movie.fixture:1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); tap(row, in: app)
        assertScreen("Details", in: app)
    }
    @MainActor private func assertGone(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }
    @MainActor private func screenshot(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
