import XCTest
import CoreGraphics
@testable import StreetlightMapper

/// Independent QA Test Suite verifying functional, negative, boundary,
/// interrupted workflow, data integrity, and security/privacy requirements.
final class IndependentQATests: XCTestCase {

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
        connectivity = ConnectivityMonitor(simulatedConnected: false)
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

    // MARK: - 1. Pole ID OCR & Validation (Boundaries & Negatives)

    func testQA_PoleID_BoundaryValidation() {
        // Boundary: 4 digits (invalid), 5 digits (min valid), 10 digits (max valid), 11 digits (invalid)
        XCTAssertFalse(PoleIDExtractor.isValid("1234"), "4 digits should be invalid")
        XCTAssertTrue(PoleIDExtractor.isValid("12345"), "5 digits is the lower boundary and should be valid")
        XCTAssertTrue(PoleIDExtractor.isValid("1234567890"), "10 digits is the upper boundary and should be valid")
        XCTAssertFalse(PoleIDExtractor.isValid("12345678901"), "11 digits should be invalid")
    }

    func testQA_PoleID_NegativeInputs() {
        // Alphanumeric, special characters, whitespace only, unicode digits
        XCTAssertFalse(PoleIDExtractor.isValid("POLE1234"))
        XCTAssertFalse(PoleIDExtractor.isValid("123-456"))
        XCTAssertFalse(PoleIDExtractor.isValid("12345 6"))
        XCTAssertFalse(PoleIDExtractor.isValid("   "))
        XCTAssertFalse(PoleIDExtractor.isValid("1234\n56"))
        XCTAssertFalse(PoleIDExtractor.isValid("<script>"))
        XCTAssertFalse(PoleIDExtractor.isValid("١٢٣٤٥"))
    }

    func testQA_PoleID_StackedDigitsThresholdCapping() {
        // Vertical stacked digits must never exceed 0.5 confidence to force manual verification
        let lines = (1...6).map { i in
            OCRLine(text: "\(i)", confidence: 1.0, box: CGRect(x: 0.5, y: 0.9 - CGFloat(i) * 0.1, width: 0.05, height: 0.05))
        }
        let extracted = PoleIDExtractor.extract(from: lines)
        XCTAssertNotNil(extracted)
        XCTAssertEqual(extracted?.value, "123456")
        XCTAssertEqual(extracted?.confidence, 0.5, "Stacked digits must be capped at 0.5 confidence")
        XCTAssertLessThan(extracted!.confidence, kHighConfidenceThreshold)
    }

    // MARK: - 2. Street Light QR Capture & Duplicate Handling

    func testQA_StreetLight_DuplicateSerialNumbersInSession() {
        // DEF-02: the same serial number cannot be added twice to one pole
        workflow.startNew()
        workflow.poleIDCaptured(poleID: "208125", confidence: .high, photoData: nil)
        XCTAssertTrue(workflow.streetLightCaptured(serial: "E5000531", confidence: .high, photoData: nil))
        workflow.addAnotherStreetLight()
        XCTAssertTrue(workflow.isDuplicateSerial("E5000531"))
        XCTAssertFalse(workflow.streetLightCaptured(serial: "E5000531", confidence: .high, photoData: Data([1])))

        XCTAssertEqual(workflow.session?.streetLights.count, 1, "duplicate is not stored")
        XCTAssertEqual(workflow.currentStep, .captureStreetLight, "stays on the scan step")
    }

    func testQA_StreetLight_WhitespaceHandling() {
        workflow.startNew()
        workflow.poleIDCaptured(poleID: "208125", confidence: .high, photoData: nil)
        workflow.streetLightCaptured(serial: "  E5000531  ", confidence: .high, photoData: nil)
        XCTAssertEqual(workflow.session?.streetLights.first?.serialNumber, "  E5000531  ",
                       "Serial number from manual entry or scan captures string as provided")
    }

    // MARK: - 3. Association Workflow & Interrupted Flow

    func testQA_Workflow_SaveWithoutPoleIDOrStreetLights() {
        // Cannot save without street lights
        workflow.startNew()
        workflow.poleIDCaptured(poleID: "208125", confidence: .high, photoData: nil)
        workflow.saveSession()
        XCTAssertFalse(workflow.isSaved)
        XCTAssertEqual(store.sessions.count, 0)
    }

    func testQA_Workflow_InterruptedByExitAndResumed() {
        workflow.startNew()
        workflow.poleIDCaptured(poleID: "208125", confidence: .high, photoData: nil)
        workflow.streetLightCaptured(serial: "E5000531", confidence: .high, photoData: nil)
        XCTAssertTrue(workflow.hasDraft)

        // Technician exits mid-workflow
        workflow.exit()
        XCTAssertFalse(workflow.isActive)
        XCTAssertTrue(workflow.hasDraft)

        // Technician resumes
        workflow.resume()
        XCTAssertTrue(workflow.isActive)
        XCTAssertEqual(workflow.session?.poleID, "208125")
        XCTAssertEqual(workflow.session?.streetLights.count, 1)

        // Add second light and save
        workflow.addAnotherStreetLight()
        workflow.streetLightCaptured(serial: "E5000532", confidence: .manual, photoData: nil)
        workflow.saveSession()
        XCTAssertTrue(workflow.isSaved)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].streetLights.count, 2)
    }

    func testQA_Workflow_ManualCorrectionUpdatesConfidenceStatus() {
        workflow.startNew()
        workflow.poleIDCaptured(poleID: "208125", confidence: .high, photoData: nil)
        workflow.streetLightCaptured(serial: "E5000531", confidence: .high, photoData: nil)
        XCTAssertEqual(workflow.session?.poleConfidence, .high)

        // Manually update Pole ID
        workflow.updatePoleID("5814901")
        XCTAssertEqual(workflow.session?.poleID, "5814901")
        XCTAssertEqual(workflow.session?.poleConfidence, .manual, "Pole confidence must become manual after edit")

        // Manually update Street Light serial
        let lightId = workflow.session!.streetLights[0].id
        workflow.updateSerial(lightID: lightId, value: "E5000999")
        XCTAssertEqual(workflow.session?.streetLights[0].serialNumber, "E5000999")
        XCTAssertEqual(workflow.session?.streetLights[0].confidence, .manual, "Light confidence must become manual after edit")
    }

    // MARK: - 4. Offline, Sync & Resilience

    func testQA_Sync_OfflinePreservesQueueWithoutLoss() {
        connectivity.simulate(connected: false)
        let s1 = TestSupport.makeSession(pole: "100001", lights: ["E1"])
        let s2 = TestSupport.makeSession(pole: "100002", lights: ["E2"])
        store.addSession(s1)
        store.addSession(s2)

        sync.syncAll()
        XCTAssertEqual(StubURLProtocol.requests.count, 0, "No network request should be dispatched when offline")
        XCTAssertEqual(store.pendingSessions().count, 2)
        XCTAssertTrue(sync.lastSyncMessage.contains("Offline"))
    }

    func testQA_Sync_PartialFailureAndRetry() {
        connectivity.simulate(connected: true)
        let s1 = TestSupport.makeSession(pole: "100001", lights: ["E1"])
        store.addSession(s1)

        // Simulate 500 server error
        StubURLProtocol.statusCode = 500
        sync.syncAll()
        XCTAssertTrue(TestSupport.wait { self.store.session(id: s1.id)?.syncStatus == .failed })

        // Server recovers to 201
        StubURLProtocol.statusCode = 201
        sync.syncAll()
        XCTAssertTrue(TestSupport.wait { self.store.session(id: s1.id)?.syncStatus == .synced })
    }

    func testQA_Sync_AppInterruptionRecovery() {
        var s = TestSupport.makeSession(pole: "208125")
        s.syncStatus = .syncing
        store.addSession(s)

        // Relaunching app store from disk
        let reloaded = SessionStore(directory: dir)
        XCTAssertEqual(reloaded.sessions[0].syncStatus, .failed,
                       "In-flight syncing status must fall back to failed upon restart to prevent stuck records")
    }

    // MARK: - 5. Data Integrity & Persistence

    func testQA_Persistence_FieldIntegrityAcrossRestarts() throws {
        var s = CaptureSession(poleID: "5814901", poleConfidence: .manual)
        let photoData = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let polePhoto = store.savePhoto(photoData, name: "pole_test.jpg")
        s.polePhotoPath = polePhoto
        s.addStreetLight(StreetLightEntry(sessionID: s.id, serialNumber: "E5000531", confidence: .high, photoPath: "photos/sl1.jpg"))
        s.addStreetLight(StreetLightEntry(sessionID: s.id, serialNumber: "E5000532", confidence: .low, photoPath: nil))
        store.addSession(s)

        let reloadedStore = SessionStore(directory: dir)
        let retrieved = try XCTUnwrap(reloadedStore.session(id: s.id))

        XCTAssertEqual(retrieved.poleID, "5814901")
        XCTAssertEqual(retrieved.poleConfidence, .manual)
        XCTAssertEqual(retrieved.polePhotoPath, polePhoto)
        XCTAssertEqual(retrieved.streetLights.count, 2)
        XCTAssertEqual(retrieved.streetLights[0].confidence, .high)
        XCTAssertEqual(retrieved.streetLights[1].confidence, .low)
        XCTAssertEqual(retrieved.syncStatus, .pending)

        let photoUrl = try XCTUnwrap(reloadedStore.photoURL(relativePath: polePhoto!))
        let readPhoto = try Data(contentsOf: photoUrl)
        XCTAssertEqual(readPhoto, photoData)
    }

    // MARK: - 6. API Contract & DTO Schema Inspection

    func testQA_API_DTOSchemaAndTypoInspection() throws {
        var session = TestSupport.makeSession(pole: "208125", lights: ["E5000531"], poleConfidence: .high)
        session.polePhotoPath = "photos/pole_sample.jpg"
        let dto = store.dto(for: session)

        let encoder = JSONEncoder()
        let data = try encoder.encode(dto)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertEqual(json?["sessionId"] as? String, session.id.uuidString)
        XCTAssertEqual(json?["poleId"] as? String, "208125")
        XCTAssertEqual(json?["poleConfidence"] as? String, "high")
        XCTAssertEqual(json?["syncStatus"] as? String, "pending")

        // DEF-04: the key is spelled correctly and the misspelled one is gone
        XCTAssertEqual(json?["polePhotoPath"] as? String, "photos/pole_sample.jpg")
        XCTAssertNil(json?["polePotoPath"])
    }

    func testQA_MockServer_HealthEndpointOnlyAnswersGET() {
        let port = UInt16.random(in: 30000...39999)       // avoid clashes with other tests
        let server = MockSAPServer()
        server.start(port: port)
        defer { server.stop() }
        XCTAssertTrue(TestSupport.wait { server.isRunning })

        func status(_ method: String) -> Int {
            let exp = expectation(description: method)
            var code = 0
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/api/v1/health")!)
            req.httpMethod = method
            URLSession(configuration: .ephemeral).dataTask(with: req) { _, resp, _ in
                code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                exp.fulfill()
            }.resume()
            wait(for: [exp], timeout: 5)
            return code
        }
        XCTAssertEqual(status("GET"), 200)
        XCTAssertEqual(status("POST"), 405)
        XCTAssertEqual(status("DELETE"), 405)
    }
}
