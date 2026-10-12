import XCTest
@testable import StreetlightMapper

final class WorkflowViewModelTests: XCTestCase {

    private var dir: URL!
    private var store: SessionStore!
    private var connectivity: ConnectivityMonitor!
    private var sync: SyncService!
    private var workflow: WorkflowViewModel!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        dir = TestSupport.tempDir()
        store = SessionStore(directory: dir)
        connectivity = ConnectivityMonitor(simulatedConnected: false)   // offline: save never uploads here
        sync = SyncService(store: store, connectivity: connectivity,
                           baseURL: URL(string: "http://stub.invalid/api/v1")!,
                           urlSession: StubURLProtocol.session(),
                           defaults: TestSupport.isolatedDefaults())
        workflow = WorkflowViewModel(store: store, sync: sync)
    }

    override func tearDown() {
        workflow = nil
        sync = nil
        connectivity = nil
        store = nil
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
        XCTAssertNotNil(workflow.session?.polePhotoPath, "photo is stored")
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
        saved.markSynced()
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

    // MARK: duplicate serial numbers (DEF-02)

    func testSameSerialCannotBeAddedTwiceToOnePole() {
        captureFullSession(lights: ["E1"])
        workflow.addAnotherStreetLight()
        XCTAssertFalse(workflow.streetLightCaptured(serial: "E1", confidence: .high, photoData: Data([9])))
        XCTAssertEqual(workflow.session?.streetLights.count, 1)
    }

    func testDuplicateCheckIgnoresCaseAndSpaces() {
        captureFullSession(lights: ["E5000531"])
        XCTAssertTrue(workflow.isDuplicateSerial("e5000531"))
        XCTAssertTrue(workflow.isDuplicateSerial("  E5000531 "))
        XCTAssertFalse(workflow.isDuplicateSerial("E5000532"))
    }

    func testRefusedDuplicateDoesNotLeaveAnOrphanPhoto() throws {
        captureFullSession(lights: ["E1"])
        let photosDir = try XCTUnwrap(store.photoURL(relativePath: "photos"))
        let before = (try? FileManager.default.contentsOfDirectory(atPath: photosDir.path))?.count ?? 0
        workflow.streetLightCaptured(serial: "E1", confidence: .high, photoData: Data([9]))
        let after = (try? FileManager.default.contentsOfDirectory(atPath: photosDir.path))?.count ?? 0
        XCTAssertEqual(before, after)
    }

    func testSameSerialIsAllowedOnADifferentPole() {
        captureFullSession(lights: ["E1"])
        workflow.saveSession()
        workflow.exit(); workflow.cleanupAfterDismiss()
        workflow.startNew()
        workflow.poleIDCaptured(poleID: "999999", confidence: .high, photoData: nil)
        XCTAssertTrue(workflow.streetLightCaptured(serial: "E1", confidence: .high, photoData: nil))
    }

    func testEditingASerialToAnotherLightsValueIsRefused() {
        captureFullSession(lights: ["E1", "E2"])
        let second = workflow.session!.streetLights[1].id
        workflow.updateSerial(lightID: second, value: "E1")
        XCTAssertEqual(workflow.session?.streetLights[1].serialNumber, "E2", "unchanged")
        XCTAssertEqual(workflow.session?.streetLights[1].confidence, .high)
    }

    func testBackToReviewNeedsAtLeastOneLight() {
        workflow.startNew()
        workflow.poleIDCaptured(poleID: "208125", confidence: .high, photoData: nil)
        workflow.backToReview()
        XCTAssertEqual(workflow.currentStep, .captureStreetLight)
        workflow.streetLightCaptured(serial: "E1", confidence: .high, photoData: nil)
        workflow.addAnotherStreetLight()
        workflow.backToReview()
        XCTAssertEqual(workflow.currentStep, .review)
    }

    // MARK: sync is separate from save

    func testSaveDoesNotUpload() {
        connectivity.simulate(connected: true)
        captureFullSession()
        workflow.saveSession()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertEqual(store.sessions[0].syncStatus, .pending)
    }

    func testSyncCurrentUploadsTheSavedCapture() {
        connectivity.simulate(connected: true)
        captureFullSession()
        workflow.saveSession()
        workflow.syncCurrent()
        XCTAssertTrue(TestSupport.wait { self.store.sessions[0].syncStatus == .synced })
        // 3 photo uploads (pole + 2 lights) followed by the one record
        XCTAssertEqual(StubURLProtocol.requests.count, 4)
        XCTAssertEqual(StubURLProtocol.requests.last?.httpMethod, "POST")
    }

    // MARK: delete (only captures the server has never received)

    func testDeleteSavedUnsyncedCaptureRemovesItAndItsPhotos() throws {
        captureFullSession()
        workflow.saveSession()
        let s = store.sessions[0]
        let photos = [s.polePhotoPath].compactMap { $0 } + s.streetLights.compactMap(\.photoPath)
        XCTAssertFalse(photos.isEmpty)
        for p in photos { XCTAssertTrue(FileManager.default.fileExists(atPath: store.photoURL(relativePath: p)!.path)) }

        XCTAssertTrue(workflow.canDeleteCurrent)
        XCTAssertTrue(workflow.deleteCurrent())

        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertFalse(workflow.hasDraft)
        XCTAssertFalse(workflow.isActive)
        for p in photos { XCTAssertFalse(FileManager.default.fileExists(atPath: store.photoURL(relativePath: p)!.path)) }
        XCTAssertTrue(SessionStore(directory: dir).sessions.isEmpty, "deletion is persisted")
    }

    func testFailedUploadCaptureCanStillBeDeleted() {
        captureFullSession()
        workflow.saveSession()
        var s = store.sessions[0]; s.syncStatus = .failed; store.updateSession(s)
        XCTAssertTrue(workflow.canDeleteCurrent)
    }

    func testSyncedCaptureCannotBeDeleted() {
        captureFullSession()
        workflow.saveSession()
        var s = store.sessions[0]; s.markSynced(); store.updateSession(s)
        XCTAssertFalse(workflow.canDeleteCurrent)
        XCTAssertFalse(workflow.deleteCurrent())
        XCTAssertEqual(store.sessions.count, 1)
    }

    func testSyncedThenEditedCaptureCannotBeDeleted() {
        captureFullSession()
        workflow.saveSession()
        var s = store.sessions[0]; s.markSynced(); store.updateSession(s)
        workflow.exit(); workflow.cleanupAfterDismiss()
        workflow.edit(store.sessions[0])
        workflow.updatePoleID("5814901")
        workflow.saveSession()                                   // back to pending, but the server has a copy
        XCTAssertEqual(store.sessions[0].syncStatus, .pending)
        XCTAssertFalse(workflow.canDeleteCurrent)
    }

    func testDeletingAnUnsavedDraftJustDiscardsIt() {
        captureFullSession()
        XCTAssertTrue(workflow.deleteCurrent())
        XCTAssertFalse(workflow.hasDraft)
        XCTAssertTrue(store.sessions.isEmpty)
    }
}
