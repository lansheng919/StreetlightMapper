import XCTest
@testable import StreetlightMapper

final class WorkflowViewModelTests: XCTestCase {

    private var dir: URL!
    private var store: SessionStore!
    private var connectivity: ConnectivityMonitor!
    private var workflow: WorkflowViewModel!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        dir = TestSupport.tempDir()
        store = SessionStore(directory: dir)
        connectivity = ConnectivityMonitor(simulatedConnected: false)   // offline: save never uploads here
        let sync = SyncService(store: store, connectivity: connectivity,
                               baseURL: URL(string: "http://stub.invalid/api/v1")!,
                               urlSession: StubURLProtocol.session())
        workflow = WorkflowViewModel(store: store, sync: sync)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func captureFullSession(lights: [String] = ["E1", "E2"]) {
        workflow.startNew()
        workflow.poleIDCaptured(poleID: "208125", confidence: .high, photoData: Data([1]))
        for l in lights { workflow.streetLightCaptured(serial: l, confidence: .high, photoData: Data([2])) }
    }

    // MARK: flow

    func testStartsOnPoleStepAndInactive() {
        XCTAssertEqual(workflow.currentStep, .capturePoloID)
        XCTAssertFalse(workflow.isActive)
        XCTAssertFalse(workflow.hasDraft)
    }

    func testStartNewOpensFlow() {
        workflow.startNew()
        XCTAssertTrue(workflow.isActive)
        XCTAssertEqual(workflow.currentStep, .capturePoloID)
    }

    func testPoleCaptureMovesToStreetLightStep() {
        workflow.startNew()
        workflow.poleIDCaptured(poleID: "208125", confidence: .high, photoData: Data([1]))
        XCTAssertEqual(workflow.currentStep, .captureStreetLight)
        XCTAssertEqual(workflow.session?.poleID, "208125")
        XCTAssertNotNil(workflow.session?.polePotoPath, "photo is stored")
    }

    func testOnePoleManyStreetLights() {
        captureFullSession(lights: ["E1", "E2", "E3"])
        XCTAssertEqual(workflow.currentStep, .review)
        XCTAssertEqual(workflow.session?.streetLights.map(\.serialNumber), ["E1", "E2", "E3"])
        workflow.addAnotherStreetLight()
        XCTAssertEqual(workflow.currentStep, .captureStreetLight)
        workflow.streetLightCaptured(serial: "E4", confidence: .manual, photoData: nil)
        XCTAssertEqual(workflow.session?.streetLights.count, 4)
        XCTAssertEqual(workflow.session?.streetLights.last?.confidence, .manual)
    }

    func testStreetLightWithoutPhotoStillRecorded() {
        workflow.startNew()
        workflow.poleIDCaptured(poleID: "208125", confidence: .high, photoData: nil)
        workflow.streetLightCaptured(serial: "E1", confidence: .high, photoData: nil)
        XCTAssertNil(workflow.session?.streetLights.first?.photoPath)
    }

    // MARK: draft: resume / discard

    func testExitKeepsDraftAndResumeRestoresIt() {
        captureFullSession()
        workflow.exit()
        XCTAssertFalse(workflow.isActive)
        XCTAssertTrue(workflow.hasDraft)
        workflow.resume()
        XCTAssertTrue(workflow.isActive)
        XCTAssertEqual(workflow.session?.streetLights.count, 2)
        XCTAssertEqual(workflow.currentStep, .review)
    }

    func testDiscardClearsDraft() {
        captureFullSession()
        workflow.exit()
        workflow.discardDraft()
        XCTAssertFalse(workflow.hasDraft)
        XCTAssertEqual(workflow.currentStep, .capturePoloID)
    }

    func testStartNewDiscardsOldDraft() {
        captureFullSession()
        workflow.exit()
        workflow.startNew()
        XCTAssertNil(workflow.session)
        XCTAssertEqual(workflow.currentStep, .capturePoloID)
    }

    func testResumeWithoutDraftStartsNew() {
        workflow.resume()
        XCTAssertTrue(workflow.isActive)
        XCTAssertEqual(workflow.currentStep, .capturePoloID)
    }

    // MARK: save

    func testSaveWritesToStoreAsPending() {
        captureFullSession()
        workflow.saveSession()
        XCTAssertTrue(workflow.isSaved)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].syncStatus, .pending, "offline: stays queued")
        XCTAssertEqual(SessionStore(directory: dir).sessions.count, 1, "persisted to disk")
    }

    func testSaveWithoutStreetLightsIsRefused() {
        workflow.startNew()
        workflow.poleIDCaptured(poleID: "208125", confidence: .high, photoData: nil)
        workflow.saveSession()
        XCTAssertFalse(workflow.isSaved)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testFinishedSessionIsClearedAfterDismiss() {
        captureFullSession()
        workflow.saveSession()
        workflow.exit()
        workflow.cleanupAfterDismiss()
        XCTAssertNil(workflow.session)
        XCTAssertFalse(workflow.hasDraft)
    }

    func testUnfinishedDraftSurvivesDismiss() {
        captureFullSession()
        workflow.exit()
        workflow.cleanupAfterDismiss()
        XCTAssertTrue(workflow.hasDraft)
    }

    // MARK: editing

    func testEditPoleIdMarksManual() {
        captureFullSession()
        workflow.updatePoleID("5814901")
        XCTAssertEqual(workflow.session?.poleID, "5814901")
        XCTAssertEqual(workflow.session?.poleConfidence, .manual)
    }

    func testEditingToSameValueKeepsConfidence() {
        captureFullSession()
        workflow.updatePoleID("208125")
        XCTAssertEqual(workflow.session?.poleConfidence, .high)
    }

    func testEditSerialMarksManual() {
        captureFullSession(lights: ["E1", "E2"])
        let id = workflow.session!.streetLights[1].id
        workflow.updateSerial(lightID: id, value: "E9")
        XCTAssertEqual(workflow.session?.streetLights[1].serialNumber, "E9")
        XCTAssertEqual(workflow.session?.streetLights[1].confidence, .manual)
        XCTAssertEqual(workflow.session?.streetLights[0].confidence, .high, "other lights untouched")
    }

    func testDeleteStreetLight() {
        captureFullSession(lights: ["E1", "E2", "E3"])
        workflow.deleteStreetLights(at: IndexSet(integer: 1))
        XCTAssertEqual(workflow.session?.streetLights.map(\.serialNumber), ["E1", "E3"])
    }

    func testCannotSaveAfterDeletingEveryLight() {
        captureFullSession(lights: ["E1"])
        workflow.deleteStreetLights(at: IndexSet(integer: 0))
        workflow.saveSession()
        XCTAssertFalse(workflow.isSaved)
    }

    func testEditingSavedSessionUpdatesInPlaceAndRequeues() {
        captureFullSession()
        workflow.saveSession()
        var saved = store.sessions[0]
        saved.syncStatus = .synced
        store.updateSession(saved)
        workflow.exit(); workflow.cleanupAfterDismiss()

        workflow.edit(store.sessions[0])
        XCTAssertTrue(workflow.isEditingExisting)
        XCTAssertEqual(workflow.currentStep, .review)
        workflow.updatePoleID("5814901")
        workflow.saveSession()

        XCTAssertEqual(store.sessions.count, 1, "no duplicate created")
        XCTAssertEqual(store.sessions[0].poleID, "5814901")
        XCTAssertEqual(store.sessions[0].syncStatus, .pending, "edited data is queued to upload again")
    }

    func testClosingEditedExistingSessionDiscardsWorkingCopy() {
        captureFullSession()
        workflow.saveSession()
        workflow.exit(); workflow.cleanupAfterDismiss()
        workflow.edit(store.sessions[0])
        workflow.updatePoleID("999999")
        workflow.exit(); workflow.cleanupAfterDismiss()
        XCTAssertFalse(workflow.hasDraft)
        XCTAssertEqual(store.sessions[0].poleID, "208125", "unsaved edit is not stored")
    }
}
