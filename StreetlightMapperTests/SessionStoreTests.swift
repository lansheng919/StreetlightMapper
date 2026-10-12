import XCTest
@testable import StreetlightMapper

final class SessionStoreTests: XCTestCase {

    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = TestSupport.tempDir()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testStartsEmpty() {
        XCTAssertTrue(SessionStore(directory: dir).sessions.isEmpty)
    }

    func testSessionsSurviveRestart() {
        let s = TestSupport.makeSession(lights: ["E1", "E2", "E3"])
        SessionStore(directory: dir).addSession(s)

        let reloaded = SessionStore(directory: dir)         // simulates relaunching the app
        XCTAssertEqual(reloaded.sessions.count, 1)
        XCTAssertEqual(reloaded.sessions.first?.poleID, "208125")
        XCTAssertEqual(reloaded.sessions.first?.streetLights.map(\.serialNumber), ["E1", "E2", "E3"])
    }

    func testPoleToManyLightsRelationshipIsKept() {
        let s = TestSupport.makeSession(lights: ["A1", "A2", "A3", "A4"])
        let store = SessionStore(directory: dir)
        store.addSession(s)
        let saved = SessionStore(directory: dir).sessions[0]
        XCTAssertEqual(saved.streetLights.count, 4)
        XCTAssertTrue(saved.streetLights.allSatisfy { $0.sessionID == saved.id })
    }

    func testConfidenceStatusIsPersisted() {
        var s = TestSupport.makeSession(lights: [], poleConfidence: .manual)
        s.addStreetLight(StreetLightEntry(sessionID: s.id, serialNumber: "H1", confidence: .high))
        s.addStreetLight(StreetLightEntry(sessionID: s.id, serialNumber: "M1", confidence: .manual))
        SessionStore(directory: dir).addSession(s)

        let saved = SessionStore(directory: dir).sessions[0]
        XCTAssertEqual(saved.poleConfidence, .manual)
        XCTAssertEqual(saved.streetLights.map(\.confidence), [.high, .manual])
    }

    func testUpdateReplacesSession() {
        var s = TestSupport.makeSession()
        let store = SessionStore(directory: dir)
        store.addSession(s)
        s.poleID = "999999"
        store.updateSession(s)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(SessionStore(directory: dir).sessions[0].poleID, "999999")
    }

    func testUpdateOfUnknownSessionIsIgnored() {
        let store = SessionStore(directory: dir)
        store.updateSession(TestSupport.makeSession())
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testDelete() {
        let a = TestSupport.makeSession(pole: "111111"), b = TestSupport.makeSession(pole: "222222")
        let store = SessionStore(directory: dir)
        store.addSession(a); store.addSession(b)
        store.deleteSession(id: a.id)
        XCTAssertEqual(store.sessions.map(\.poleID), ["222222"])
        XCTAssertEqual(SessionStore(directory: dir).sessions.count, 1)
    }

    func testPendingSessionsIncludesPendingAndFailedOnly() {
        let store = SessionStore(directory: dir)
        for status in [SyncStatus.pending, .failed, .synced, .syncing] {
            var s = TestSupport.makeSession(pole: "\(status.rawValue)")
            s.syncStatus = status
            store.addSession(s)
        }
        XCTAssertEqual(Set(store.pendingSessions().map(\.poleID)), ["pending", "failed"])
    }

    func testCanDeleteOnlyWhenServerNeverReceivedIt() {
        var s = TestSupport.makeSession()
        XCTAssertTrue(s.canDelete)
        s.syncStatus = .failed
        XCTAssertTrue(s.canDelete)
        s.syncStatus = .syncing
        XCTAssertFalse(s.canDelete, "an upload is in flight")
        s.markSynced()
        XCTAssertFalse(s.canDelete)
        s.syncStatus = .pending                     // edited after syncing; the server still has a copy
        XCTAssertFalse(s.canDelete)
    }

    func testDeleteRemovesPhotoFiles() throws {
        let store = SessionStore(directory: dir)
        var s = TestSupport.makeSession(lights: [])
        let path = try XCTUnwrap(store.savePhoto(Data([1, 2, 3]), name: "sl_del.jpg"))
        s.addStreetLight(StreetLightEntry(sessionID: s.id, serialNumber: "E1", confidence: .high, photoPath: path))
        store.addSession(s)
        let url = try XCTUnwrap(store.photoURL(relativePath: path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        store.deleteSession(id: s.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDeleteAllRemovesEverythingIncludingSyncedAndPhotos() throws {
        let store = SessionStore(directory: dir)
        var synced = TestSupport.makeSession(pole: "111111", lights: [])
        let path = try XCTUnwrap(store.savePhoto(Data([1]), name: "pole_all.jpg"))
        synced.polePhotoPath = path
        synced.addStreetLight(StreetLightEntry(sessionID: synced.id, serialNumber: "E1", confidence: .high))
        synced.markSynced()
        store.addSession(synced)
        store.addSession(TestSupport.makeSession(pole: "222222"))

        store.deleteAll()

        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.photoURL(relativePath: path)!.path))
        XCTAssertTrue(SessionStore(directory: dir).sessions.isEmpty, "reset is persisted")
        XCTAssertNotNil(store.savePhoto(Data([2]), name: "after.jpg"), "photos folder is recreated on demand")
    }

    func testInterruptedUploadBecomesFailedOnLoad() {
        let store = SessionStore(directory: dir)
        var s = TestSupport.makeSession()
        store.addSession(s)
        s.syncStatus = .syncing
        store.updateSession(s)
        let reloaded = SessionStore(directory: dir)
        XCTAssertEqual(reloaded.sessions[0].syncStatus, .failed)
        XCTAssertTrue(reloaded.sessions[0].canDelete)
    }

    func testSessionSyncedByOlderVersionIsStillProtectedFromDelete() throws {
        let store = SessionStore(directory: dir)
        var s = TestSupport.makeSession()
        s.syncStatus = .synced                      // no lastSyncedAt, like data saved before this feature
        store.addSession(s)
        var reloaded = try XCTUnwrap(SessionStore(directory: dir).sessions.first)
        XCTAssertNotNil(reloaded.lastSyncedAt)
        reloaded.syncStatus = .pending
        XCTAssertFalse(reloaded.canDelete)
    }

    /// Captures saved before the key was corrected (DEF-04) keep their pole photo.
    func testCaptureSavedWithOldMisspelledKeyStillLoadsItsPhoto() throws {
        let id = UUID().uuidString
        let json = """
        [{"id":"\(id)","poleID":"208125","poleConfidence":"high","polePotoPath":"photos/old.jpg",
          "streetLights":[],"syncStatus":"pending","createdAt":"2026-10-11T00:00:00Z","updatedAt":"2026-10-11T00:00:00Z"}]
        """
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appendingPathComponent("sessions.json"))

        let loaded = SessionStore(directory: dir)
        XCTAssertEqual(loaded.sessions.count, 1)
        XCTAssertEqual(loaded.sessions[0].polePhotoPath, "photos/old.jpg")

        // Saving again writes the corrected key only.
        loaded.updateSession(loaded.sessions[0])
        let text = try String(contentsOf: dir.appendingPathComponent("sessions.json"))
        XCTAssertTrue(text.contains("polePhotoPath"))
        XCTAssertFalse(text.contains("polePotoPath"))
    }

    func testPhotoRoundTrip() throws {
        let store = SessionStore(directory: dir)
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        let path = try XCTUnwrap(store.savePhoto(bytes, name: "pole_test.jpg"))
        XCTAssertEqual(path, "photos/pole_test.jpg")
        let url = try XCTUnwrap(store.photoURL(relativePath: path))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testCorruptFileDoesNotCrashAndStartsEmpty() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("sessions.json"))
        XCTAssertTrue(SessionStore(directory: dir).sessions.isEmpty)
    }

    // MARK: REST DTO

    func testDTOMatchesRESTContract() throws {
        var s = TestSupport.makeSession(pole: "5814901", lights: [], poleConfidence: .high)
        s.addStreetLight(StreetLightEntry(sessionID: s.id, serialNumber: "E5000531", confidence: .manual, photoPath: "photos/x.jpg"))
        let dto = SessionStore(directory: dir).dto(for: s)

        XCTAssertEqual(dto.sessionId, s.id.uuidString)
        XCTAssertEqual(dto.poleId, "5814901")
        XCTAssertEqual(dto.poleConfidence, "high")
        XCTAssertEqual(dto.syncStatus, "pending")
        XCTAssertEqual(dto.streetLights.count, 1)
        XCTAssertEqual(dto.streetLights[0].serialNumber, "E5000531")
        XCTAssertEqual(dto.streetLights[0].confidence, "manual")
        XCTAssertEqual(dto.streetLights[0].photoPath, "photos/x.jpg")

        // JSON field names are what SAP integrations will depend on
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(dto)) as? [String: Any]
        for key in ["sessionId", "poleId", "poleConfidence", "streetLights", "createdAt", "syncStatus"] {
            XCTAssertNotNil(json?[key], "missing \(key)")
        }
    }
}
