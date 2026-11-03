import XCTest

final class BetaPreparationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testDeviceCredentialSettingsAndCreditsUseIsolatedTestStore() {
        let app = launch()
        app.tabBars.buttons["Profile"].tap()
        reveal(app.buttons["profile.settings"], app); app.buttons["profile.settings"].tap()
        let token = app.secureTextFields["settings.token"]
        XCTAssertTrue(token.waitForExistence(timeout: 5))
        let settingsShot = XCTAttachment(screenshot: app.screenshot())
        settingsShot.name = "Settings — before entering a credential"
        settingsShot.lifetime = .keepAlways
        add(settingsShot)
        token.tap(); token.typeText("nonsecret-ui-fixture")
        let save = app.buttons["settings.saveCredential"]; reveal(save, app); save.tap()
        XCTAssertTrue(app.staticTexts["settings.credentialStatus"].label.contains("saved on this device"))
        let remove = app.buttons["settings.removeCredential"]; reveal(remove, app); remove.tap()
        app.buttons["Remove Credential"].tap()
        XCTAssertEqual(app.staticTexts["settings.credentialStatus"].label, "No device credential saved.")
        let credits = app.buttons["About & Credits"]; reveal(credits, app); credits.tap()
        XCTAssertTrue(app.staticTexts["credits.tmdbNotice"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Beta provider credits"
        attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testSearchFiltersRemainUsableAtLargestAccessibilitySize() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.tabBars.buttons["Search"].tap()
        let filter = app.buttons["search.filters"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5)); reveal(filter, app); filter.tap()
        app.buttons["Movies"].tap()
        let field = app.searchFields["Movies and TV shows"]; field.tap(); field.typeText("sample")
        let result = app.buttons["search.result.movie.fixture:1"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); reveal(result, app)
        XCTAssertTrue(result.isHittable)
        XCTAssertFalse(app.buttons["search.result.tvShow.fixture:1"].exists)
    }
    @MainActor func testMetadataPolicyAndApprovedAttributionAreVisibleOffline() {
        let app = launch()
        app.tabBars.buttons["Profile"].tap()
        let credits = app.buttons["profile.credits"]; reveal(credits, app); credits.tap()
        XCTAssertTrue(app.staticTexts["credits.tmdbNotice"].waitForExistence(timeout: 5))
        let logo = app.images["credits.tmdbLogo"]; reveal(logo, app); XCTAssertTrue(logo.exists)
        let policy = app.staticTexts["credits.cachePolicy"]; reveal(policy, app)
        XCTAssertTrue(policy.label.contains("150 days")); XCTAssertTrue(policy.label.contains("identifier placeholder"))
    }

    @MainActor private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-search", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        XCTAssertTrue(app.navigationBars["Home"].waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<25 {
            if element.exists && element.isHittable { return }
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
}
