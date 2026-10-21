import XCTest

// End-to-end UI checks in the simulator. The simulator has no camera, so these cover
// everything around it: start page, navigation, review/edit, permissions and offline state.
// The app is launched with a throw-away database (see StreetlightMapperApp).

final class StreetlightMapperUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(seeded: Bool = false, offline: Bool = false, syncedSeed: Bool = false) {
        app = XCUIApplication()
        var args = ["-UITesting"]
        if seeded { args.append("-UITestingSeed") }
        if syncedSeed { args.append("-UITestingSeedSynced") }
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
        XCTAssertTrue(app.navigationBars["PoleLink"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["Saved on this phone. Sync it now or later from Home."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Capture Another Pole"].exists)
        XCTAssertFalse(app.buttons["review.syncNow"].isEnabled, "Sync Now is disabled while offline")
    }

    // MARK: sync is a separate action

    func testHomeShowsUnsyncedCaptureWithSyncAllButton() {
        launch(seeded: true)
        XCTAssertTrue(app.staticTexts["1 capture saved on this phone, not yet synced"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.syncAll"].isEnabled)
    }

    func testHomeSyncAllMarksCaptureSynced() {
        launch(seeded: true)
        tap(app.buttons["home.syncAll"])
        XCTAssertTrue(app.staticTexts["1 synced"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["1 capture saved on this phone, not yet synced"].exists)
    }

    func testHomeSyncDisabledWhenOffline() {
        launch(seeded: true, offline: true)
        XCTAssertTrue(app.buttons["home.syncAll"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home.syncAll"].isEnabled)
        XCTAssertTrue(app.staticTexts["You are offline. Sync later when you have a connection."].exists)
    }

    func testSyncNowFromReviewAfterSave() {
        launch(seeded: true)
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        tap(app.buttons["Save Changes"])
        XCTAssertTrue(app.staticTexts["Saved on this phone. Sync it now or later from Home."].waitForExistence(timeout: 5))
        tap(app.buttons["review.syncNow"])
        XCTAssertTrue(app.staticTexts["Saved and synced to the server."].waitForExistence(timeout: 10))
    }

    func testAutoSyncToggleIsOffByDefault() {
        launch()
        tap(app.tabBars.buttons["Integration"])
        let toggle = app.switches["debug.autoSync"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
    }

    // MARK: delete

    func testDeleteUnsyncedCaptureFromReview() {
        launch(seeded: true)
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        tap(app.buttons["review.delete"])
        XCTAssertTrue(app.buttons["Yes, Delete"].waitForExistence(timeout: 5))
        tap(app.buttons["Yes, Delete"])
        XCTAssertTrue(app.buttons["Start New Capture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Recent captures"].exists, "capture is gone")
    }

    func testCancellingDeleteKeepsCapture() {
        launch(seeded: true)
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        tap(app.buttons["review.delete"])
        XCTAssertTrue(app.buttons["Yes, Delete"].waitForExistence(timeout: 5))
        tap(app.buttons["Keep it"])
        XCTAssertTrue(app.navigationBars["Edit Capture"].exists)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Recent captures"].waitForExistence(timeout: 5))
    }

    func testSyncedCaptureHasNoDeleteButton() {
        launch(syncedSeed: true)
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        XCTAssertTrue(app.navigationBars["Edit Capture"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.delete"].exists)
        XCTAssertTrue(app.staticTexts["Already sent to the server, so it can't be deleted here."].exists)
    }

    // MARK: duplicate serial numbers

    func testEditingSerialToAnExistingOneIsBlockedWithMessage() {
        launch(seeded: true)                         // lights E5000531 and E5000532
        tap(app.buttons.containing(.staticText, identifier: "208125").firstMatch)
        tap(app.buttons.containing(.staticText, identifier: "E5000532").firstMatch)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.clearAndType("E5000531")
        XCTAssertTrue(app.staticTexts["edit.duplicateError"].waitForExistence(timeout: 5)
                      || app.staticTexts["This serial number is already captured."].exists)
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        field.clearAndType("E5000599")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
    }

    func testDeleteAllCapturesFromIntegrationTab() {
        launch(syncedSeed: true)                      // even a synced capture is wiped by the reset
        tap(app.tabBars.buttons["Integration"])
        let button = app.buttons["debug.deleteAll"]
        app.swipeUp()
        tap(button)
        tap(app.buttons["Yes, Delete All"])
        tap(app.tabBars.buttons["History"])
        XCTAssertTrue(app.staticTexts["No sessions yet"].waitForExistence(timeout: 5))
    }

    func testDeleteFromHistoryDetail() {
        launch(seeded: true)
        tap(app.tabBars.buttons["History"])
        tap(app.staticTexts["208125"])
        tap(app.buttons["detail.delete"])
        tap(app.buttons["Yes, Delete"])
        XCTAssertTrue(app.staticTexts["No sessions yet"].waitForExistence(timeout: 5))
    }

    func testHistoryDetailOfSyncedCaptureCannotDelete() {
        launch(syncedSeed: true)
        tap(app.tabBars.buttons["History"])
        tap(app.staticTexts["208125"])
        XCTAssertTrue(app.staticTexts["E5000531"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["detail.delete"].exists)
        XCTAssertFalse(app.buttons["detail.sync"].exists)
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
