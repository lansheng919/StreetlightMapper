import XCTest
@testable import StreetlightMapper

// Requirement 5: capture offline, sync when connectivity returns.

final class SyncServiceTests: XCTestCase {

    private var dir: URL!
    private var store: SessionStore!
    private var connectivity: ConnectivityMonitor!
    private var sync: SyncService!
    private let base = URL(string: "http://stub.invalid/api/v1")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        dir = TestSupport.tempDir()
        store = SessionStore(directory: dir)
    }

    override func tearDown() {
        // XCTest keeps finished test objects alive. Release the service so its delayed
        // auto-sync (2 s after creation while online) cannot fire during a later test.
        sync = nil
        connectivity = nil
        store = nil
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func makeSync(connected: Bool, defaults: UserDefaults = TestSupport.isolatedDefaults()) {
        connectivity = ConnectivityMonitor(simulatedConnected: connected)
        sync = SyncService(store: store, connectivity: connectivity, baseURL: base,
                           urlSession: StubURLProtocol.session(), defaults: defaults)
    }

    // MARK: sync is a separate, manual action

    func testAutoSyncIsOffByDefault() {
        makeSync(connected: true)
        XCTAssertFalse(sync.autoSyncEnabled)
    }

    func testAutoSyncSettingIsPersisted() {
        let defaults = TestSupport.isolatedDefaults()
        makeSync(connected: true, defaults: defaults)
        sync.autoSyncEnabled = true
        let again = SyncService(store: store, connectivity: connectivity, baseURL: base,
                                urlSession: StubURLProtocol.session(), defaults: defaults)
        XCTAssertTrue(again.autoSyncEnabled)
    }

    func testReconnectDoesNotUploadWhileAutoSyncIsOff() {
        makeSync(connected: false)
        store.addSession(TestSupport.makeSession())
        connectivity.simulate(connected: true)
        RunLoop.main.run(until: Date().addingTimeInterval(3))     // longer than the 2 s debounce
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "nothing is sent until the technician syncs")
        XCTAssertEqual(store.sessions[0].syncStatus, .pending)
    }

    func testSyncSingleSessionLeavesOthersQueued() {
        makeSync(connected: true)
        let a = TestSupport.makeSession(pole: "111111")
        let b = TestSupport.makeSession(pole: "222222")
        store.addSession(a); store.addSession(b)
        sync.sync(sessionID: b.id)
        XCTAssertTrue(TestSupport.wait { self.store.session(id: b.id)?.syncStatus == .synced })
        XCTAssertEqual(store.session(id: a.id)?.syncStatus, .pending)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testSyncedSessionRecordsTimeAndCannotBeDeleted() {
        makeSync(connected: true)
        let s = TestSupport.makeSession()
        store.addSession(s)
        XCTAssertTrue(store.session(id: s.id)!.canDelete)
        sync.syncAll()
        XCTAssertTrue(TestSupport.wait { self.store.session(id: s.id)?.syncStatus == .synced })
        XCTAssertNotNil(store.session(id: s.id)?.lastSyncedAt)
        XCTAssertFalse(store.session(id: s.id)!.canDelete)
    }

    // MARK: photos are uploaded (DEF-03)

    private func sessionWithPhotos() -> CaptureSession {
        var s = CaptureSession(poleID: "208125", poleConfidence: .high,
                               polePhotoPath: store.savePhoto(Data([0xFF, 0xD8, 1, 2]), name: "pole_a.jpg"))
        s.addStreetLight(StreetLightEntry(sessionID: s.id, serialNumber: "E1", confidence: .high,
                                          photoPath: store.savePhoto(Data([0xFF, 0xD8, 3]), name: "sl_a.jpg")))
        s.addStreetLight(StreetLightEntry(sessionID: s.id, serialNumber: "E2", confidence: .manual,
                                          photoPath: store.savePhoto(Data([0xFF, 0xD8, 4]), name: "sl_b.jpg")))
        return s
    }

    func testPhotosAreUploadedAsRawJPEGBeforeTheRecord() {
        makeSync(connected: true)
        store.addSession(sessionWithPhotos())
        sync.syncAll()
        XCTAssertTrue(TestSupport.wait { self.store.sessions[0].syncStatus == .synced })

        let methods = StubURLProtocol.requests.map { $0.httpMethod ?? "" }
        XCTAssertEqual(methods.filter { $0 == "PUT" }.count, 3, "pole photo + two street light photos")
        XCTAssertEqual(methods.last, "POST", "the record is sent only after every photo")

        let urls = StubURLProtocol.requests.filter { $0.httpMethod == "PUT" }.compactMap { $0.url?.absoluteString }
        XCTAssertEqual(Set(urls), ["http://stub.invalid/api/v1/photos/pole_a.jpg",
                                   "http://stub.invalid/api/v1/photos/sl_a.jpg",
                                   "http://stub.invalid/api/v1/photos/sl_b.jpg"])
        XCTAssertEqual(StubURLProtocol.requests.first { $0.httpMethod == "PUT" }?.value(forHTTPHeaderField: "Content-Type"),
                       "image/jpeg")
        XCTAssertTrue(StubURLProtocol.bodies.contains(Data([0xFF, 0xD8, 1, 2])), "actual image bytes are sent")
    }

    func testFailedPhotoUploadStopsTheRecordAndKeepsItQueued() {
        makeSync(connected: true)
        StubURLProtocol.statusCode = 500
        store.addSession(sessionWithPhotos())
        sync.syncAll()
        XCTAssertTrue(TestSupport.wait { self.store.sessions[0].syncStatus == .failed })
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.httpMethod == "POST" },
                       "no record is created on the server when its photos did not arrive")
        XCTAssertTrue(store.sessions[0].canDelete)
    }

    func testCaptureWithoutPhotosStillSyncs() {
        makeSync(connected: true)
        store.addSession(TestSupport.makeSession())
        sync.syncAll()
        XCTAssertTrue(TestSupport.wait { self.store.sessions[0].syncStatus == .synced })
        XCTAssertEqual(StubURLProtocol.requests.map { $0.httpMethod }, ["POST"])
    }

    // MARK: offline

    func testOfflineKeepsSessionsQueuedAndSendsNothing() {
        makeSync(connected: false)
        store.addSession(TestSupport.makeSession())
        sync.syncAll()
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "no network calls while offline")
        XCTAssertEqual(store.sessions[0].syncStatus, .pending)
        XCTAssertTrue(sync.lastSyncMessage.contains("Offline"))
    }

    func testSyncsAutomaticallyWhenConnectivityReturnsIfEnabled() {
        makeSync(connected: false)
        sync.autoSyncEnabled = true
        store.addSession(TestSupport.makeSession(pole: "111111"))
        store.addSession(TestSupport.makeSession(pole: "222222"))

        connectivity.simulate(connected: true)              // network comes back; service debounces 2s

        XCTAssertTrue(TestSupport.wait(timeout: 8) { self.store.sessions.allSatisfy { $0.syncStatus == .synced } },
                      "queued sessions upload by themselves")
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    // MARK: online

    func testOnlineSyncMarksSynced() {
        makeSync(connected: true)
        store.addSession(TestSupport.makeSession())
        sync.syncAll()
        XCTAssertTrue(TestSupport.wait { self.store.sessions[0].syncStatus == .synced })
        XCTAssertFalse(sync.isSyncing)
    }

    func testRequestShape() throws {
        makeSync(connected: true)
        let s = TestSupport.makeSession(pole: "5814901", lights: ["E1", "E2"])
        store.addSession(s)
        sync.syncAll()
        XCTAssertTrue(TestSupport.wait { !StubURLProtocol.requests.isEmpty && !StubURLProtocol.bodies.isEmpty })

        let req = StubURLProtocol.requests[0]
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.absoluteString, "http://stub.invalid/api/v1/sessions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let dto = try JSONDecoder().decode(SessionDTO.self, from: StubURLProtocol.bodies[0])
        XCTAssertEqual(dto.poleId, "5814901")
        XCTAssertEqual(dto.streetLights.map(\.serialNumber), ["E1", "E2"])
    }

    func testServerErrorMarksFailedAndItRetriesLater() {
        makeSync(connected: true)
        StubURLProtocol.statusCode = 500
        store.addSession(TestSupport.makeSession())
        sync.syncAll()
        XCTAssertTrue(TestSupport.wait { self.store.sessions[0].syncStatus == .failed })

        StubURLProtocol.statusCode = 201                    // server recovers
        sync.syncAll()
        XCTAssertTrue(TestSupport.wait { self.store.sessions[0].syncStatus == .synced },
                      "failed sessions are retried")
    }

    func testNetworkErrorMarksFailed() {
        makeSync(connected: true)
        StubURLProtocol.failWithError = true
        store.addSession(TestSupport.makeSession())
        sync.syncAll()
        XCTAssertTrue(TestSupport.wait { self.store.sessions[0].syncStatus == .failed })
    }

    func testAlreadySyncedSessionsAreNotResent() {
        makeSync(connected: true)
        var s = TestSupport.makeSession()
        s.syncStatus = .synced
        store.addSession(s)
        sync.syncAll()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testMixedBatchOnlySendsPending() {
        makeSync(connected: true)
        var done = TestSupport.makeSession(pole: "111111"); done.syncStatus = .synced
        store.addSession(done)
        store.addSession(TestSupport.makeSession(pole: "222222"))
        sync.syncAll()
        XCTAssertTrue(TestSupport.wait { self.store.sessions.allSatisfy { $0.syncStatus == .synced } })
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }
}
