import XCTest

// End-to-end UI checks in the simulator. The simulator has no camera, so these cover
// everything around it: start page, navigation, review/edit, permissions and offline state.
// The app is launched with a throw-away database (see StreetlightMapperApp).

final class StreetlightMapperUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(seeded: Bool = false, offline: Bool = false) {
        app = XCUIApplication()
        var args = ["-UITesting"]
        if seeded { args.append("-UITestingSeed") }
        if offline { args.append("-UITestingOffline") }
        app.launchArguments = args
        app.launch()
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) not found", file: file, line: line)
        element.tap()
    }

    // MARK: start page

    func testLaunchShowsStartPageNotCamera() {
        launch()
        XCTAssertTrue(app.navigationBars["Streetlight Mapper"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start New Capture"].exists)
        XCTAssertTrue(app.staticTexts["How it works"].exists)
        XCTAssertTrue(app.staticTexts["1. Scan the Pole ID"].exists)
        XCTAssertTrue(app.staticTexts["2. Scan each street light"].exists)
        XCTAssertTrue(app.staticTexts["3. Check and save"].exists)
        XCTAssertFalse(app.buttons["Close camera"].exists, "camera must not open on launch")
    }

    func testTabsExist() {
        launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["History"].exists)
        XCTAssertTrue(app.tabBars.buttons["Integration"].exists)
    }

    func testOnlineAndOfflineChips() {
        launch()
        XCTAssertTrue(app.staticTexts["Online"].waitForExistence(timeout: 5))
        app.terminate()
        launch(offline: true)
        XCTAssertTrue(app.staticTexts["Offline – saving locally"].waitForExistence(timeout: 5))
    }

    func testNoRecentSectionWhenEmpty() {
        launch()
        XCTAssertFalse(app.staticTexts["Recent captures"].exists)
    }

    // MARK: capture flow open/close

    func testStartCaptureOpensFullScreenFlowAndCloses() {
        launch()
        tap(app.buttons["Start New Capture"])
        XCTAssertTrue(app.staticTexts["Step 1 of 2 · Pole ID"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Close camera"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "capture is full screen, tab bar hidden")

        tap(app.buttons["Close camera"])
        XCTAssertTrue(app.buttons["Start New Capture"].waitForExistence(timeout: 5))
    }

    func testNoResumeCardWhenNothingWasCaptured() {
        launch()
        tap(app.buttons["Start New Capture"])
        tap(app.buttons["Close camera"])
        XCTAssertTrue(app.buttons["Start New Capture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Unfinished capture"].exists)
    }

    // MARK: recent + edit

    func testSeededCaptureAppearsInRecent() {
        launch(seeded: true)
        XCTAssertTrue(app.staticTexts["Recent captures"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["208125"].exists)
        XCTAssertTrue(app.staticTexts["2 street light(s)"].exists)
    }

    func testEditFromRecentOpensReviewWithValues() {
        launch(seeded: true)
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        XCTAssertTrue(app.navigationBars["Edit Capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["208125"].exists)
        XCTAssertTrue(app.staticTexts["E5000531"].exists)
        XCTAssertTrue(app.staticTexts["E5000532"].exists)
        XCTAssertTrue(app.staticTexts["AUTO"].exists)
        XCTAssertTrue(app.staticTexts["MANUAL"].exists)
    }

    func testCorrectPoleIdInReview() {
        launch(seeded: true)
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        XCTAssertTrue(app.navigationBars["Edit Capture"].waitForExistence(timeout: 5))

        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.clearAndType("5814901")
        tap(app.buttons["Save"])

        XCTAssertTrue(app.staticTexts["5814901"].waitForExistence(timeout: 5))
        // The Home page's Recent row sits behind the full-screen cover; only visible text counts.
        XCTAssertFalse(app.staticTexts["208125"].isHittable, "old Pole ID no longer shown on the review screen")
    }

    func testPoleIdValidationBlocksSavingBadValue() {
        launch(seeded: true)
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.clearAndType("12")
        XCTAssertFalse(app.buttons["Save"].isEnabled, "2 digits is not a valid Pole ID")
        field.clearAndType("123456")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
    }

    func testSaveEditedCaptureShowsBannerAndQueuesOffline() {
        launch(seeded: true, offline: true)
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        tap(app.buttons["Save Changes"])
        XCTAssertTrue(app.staticTexts["Saved. It will upload as soon as you are online."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Capture Another Pole"].exists)
    }

    func testDeletingAllLightsDisablesSave() {
        launch(seeded: true)
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        XCTAssertTrue(app.buttons["Save Changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save Changes"].isEnabled)

        for _ in 0..<2 {
            let cell = app.cells.containing(.staticText, identifier: "Light 1").firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 5))
            cell.swipeLeft()
            tap(app.buttons["Delete"])
        }
        XCTAssertTrue(app.staticTexts["No street lights yet. Add at least one to save."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save Changes"].isEnabled)
    }

    func testCloseWithUnsavedEditsAsksToDiscard() {
        launch(seeded: true)
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.clearAndType("999999")
        tap(app.buttons["Save"])

        tap(app.buttons["Close"])
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        tap(app.buttons["Discard changes"])
        XCTAssertTrue(app.buttons["Start New Capture"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["208125"].isHittable, "unsaved edit was thrown away")
        XCTAssertFalse(app.staticTexts["999999"].exists)
    }

    // MARK: history

    func testHistoryListsCaptureAndDetailHasEdit() {
        launch(seeded: true)
        tap(app.tabBars.buttons["History"])
        XCTAssertTrue(app.navigationBars["Captured Sessions"].waitForExistence(timeout: 5))
        tap(app.staticTexts["208125"])
        XCTAssertTrue(app.staticTexts["E5000531"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Edit"].exists)
    }

    func testHistoryEmptyState() {
        launch()
        tap(app.tabBars.buttons["History"])
        XCTAssertTrue(app.staticTexts["No sessions yet"].waitForExistence(timeout: 5))
    }

    func testSeeAllJumpsToHistory() {
        launch(seeded: true)
        tap(app.buttons["See all"])
        XCTAssertTrue(app.navigationBars["Captured Sessions"].waitForExistence(timeout: 5))
    }

    // MARK: integration tab

    func testIntegrationTabShowsMockSapServer() {
        launch()
        tap(app.tabBars.buttons["Integration"])
        XCTAssertTrue(app.staticTexts["Mock SAP Server"].waitForExistence(timeout: 5)
                      || app.staticTexts["MOCK SAP SERVER"].waitForExistence(timeout: 2))
    }
}

private extension XCUIElement {
    /// Replaces the text of a text field.
    func clearAndType(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty, current != "5 to 10 digits", current != "Serial number" {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
