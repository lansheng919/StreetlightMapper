import XCTest
import Network
@testable import StreetlightMapper

// Requirement 4: REST API usable without a live SAP. These talk to the real embedded
// server over HTTP on a test port.

final class MockSAPServerTests: XCTestCase {

    private var server: MockSAPServer!
    private var port: UInt16 = 0
    private var base: String { "http://127.0.0.1:\(port)/api/v1" }

    /// A fresh port per test: a stopped listener releases its port asynchronously.
    private static var nextPort: UInt16 = 18080

    override func setUpWithError() throws {
        try super.setUpWithError()
        port = Self.nextPort
        Self.nextPort += 1
        server = MockSAPServer()
        server.start(port: port)
        XCTAssertTrue(TestSupport.wait(timeout: 5) { self.server.isRunning }, "server did not start")
    }

    override func tearDown() {
        server.stop()
        super.tearDown()
    }

    // MARK: helpers

    private func call(_ method: String, _ path: String, body: String? = nil) throws -> (status: Int, body: String) {
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = method
        req.timeoutInterval = 5
        if let body {
            req.httpBody = Data(body.utf8)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let done = expectation(description: "\(method) \(path)")
        var result: (Int, String)?
        URLSession(configuration: .ephemeral).dataTask(with: req) { data, resp, _ in
            result = ((resp as? HTTPURLResponse)?.statusCode ?? -1, String(data: data ?? Data(), encoding: .utf8) ?? "")
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 6)
        return try XCTUnwrap(result)
    }

    private func sessionJSON(id: String = "11111111-1111-1111-1111-111111111111", pole: String = "208125") -> String {
        """
        {"sessionId":"\(id)","poleId":"\(pole)","poleConfidence":"high",
         "streetLights":[{"id":"a1","serialNumber":"E5000531","confidence":"high","capturedAt":"2026-10-11T00:00:00Z"},
                         {"id":"a2","serialNumber":"E5000532","confidence":"manual","capturedAt":"2026-10-11T00:01:00Z"}],
         "createdAt":"2026-10-11T00:00:00Z","syncStatus":"pending"}
        """
    }

    // MARK: tests

    /// Headers and body arriving in separate TCP segments must still be handled as one request.
    func testPostWithHeadersAndBodySentSeparately() throws {
        let body = sessionJSON(id: "BBBBBBBB-0000-0000-0000-000000000009")
        let head = "POST /api/v1/sessions HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n" +
                   "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        let conn = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let replied = expectation(description: "reply")
        var reply = ""
        conn.stateUpdateHandler = { state in
            guard case .ready = state else { return }
            conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {      // body arrives later
                    conn.send(content: Data(body.utf8), completion: .contentProcessed { _ in })
                }
            })
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                reply = String(data: data ?? Data(), encoding: .utf8) ?? ""
                replied.fulfill()
            }
        }
        conn.start(queue: .global())
        wait(for: [replied], timeout: 6)
        conn.cancel()
        XCTAssertTrue(reply.hasPrefix("HTTP/1.1 201"), "got: \(reply.prefix(40))")
        XCTAssertTrue(TestSupport.wait { self.server.receivedSessions.count == 1 })
    }

    // MARK: photos (DEF-03)

    private func putPhoto(_ name: String, _ bytes: Data) throws -> Int {
        var req = URLRequest(url: URL(string: base + "/photos/" + name)!)
        req.httpMethod = "PUT"
        req.httpBody = bytes
        req.timeoutInterval = 5
        let done = expectation(description: "PUT \(name)")
        var status = 0
        URLSession(configuration: .ephemeral).dataTask(with: req) { _, resp, _ in
            status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 6)
        return status
    }

    func testPhotoPutThenGetReturnsIdenticalBytes() throws {
        // Includes bytes that are invalid UTF-8 and CRLFCRLF, as real JPEG data can contain.
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x0D, 0x0A, 0x0D, 0x0A, 0xFE, 0x80, 0x00, 0xFF, 0xD9])
        XCTAssertEqual(try putPhoto("pole_t.jpg", jpeg), 201)
        XCTAssertEqual(server.photo(named: "photos/pole_t.jpg"), jpeg)

        let done = expectation(description: "GET")
        var got = Data(); var type = ""
        URLSession(configuration: .ephemeral).dataTask(with: URL(string: base + "/photos/pole_t.jpg")!) { data, resp, _ in
            got = data ?? Data()
            type = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 6)
        XCTAssertEqual(got, jpeg)
        XCTAssertEqual(type, "image/jpeg")
        XCTAssertTrue(TestSupport.wait { self.server.receivedPhotoCount == 1 })
    }

    func testMissingPhotoIs404AndEmptyPutIsRejected() throws {
        XCTAssertEqual(try call("GET", "/photos/nope.jpg").status, 404)
        XCTAssertEqual(try putPhoto("empty.jpg", Data()), 422)
        XCTAssertNil(server.photo(named: "photos/empty.jpg"))
    }

    func testHealthRejectsNonGet() throws {
        XCTAssertEqual(try call("POST", "/health", body: "{}").status, 405)
    }

    func testHealth() throws {
        let r = try call("GET", "/health")
        XCTAssertEqual(r.status, 200)
        XCTAssertTrue(r.body.contains("\"ok\""))
    }

    func testPostThenListAndGet() throws {
        XCTAssertEqual(try call("POST", "/sessions", body: sessionJSON()).status, 201)

        let list = try call("GET", "/sessions")
        XCTAssertEqual(list.status, 200)
        XCTAssertTrue(list.body.contains("208125"))
        XCTAssertTrue(list.body.contains("E5000532"))

        let one = try call("GET", "/sessions/11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(one.status, 200)
        XCTAssertTrue(one.body.contains("E5000531"))
    }

    func testConfidenceStatusIsExposedPerLight() throws {
        _ = try call("POST", "/sessions", body: sessionJSON())
        let body = try call("GET", "/sessions").body
        XCTAssertTrue(body.contains("\"manual\""))
        XCTAssertTrue(body.contains("\"high\""))
    }

    func testUnknownSessionIs404() throws {
        XCTAssertEqual(try call("GET", "/sessions/does-not-exist").status, 404)
    }

    func testMalformedBodyIs422AndNothingStored() throws {
        XCTAssertEqual(try call("POST", "/sessions", body: "{bad json").status, 422)
        XCTAssertEqual(try call("GET", "/sessions").body, "[]")
    }

    func testUnknownRouteIs404() throws {
        XCTAssertEqual(try call("GET", "/nope").status, 404)
    }

    func testResubmittingSameSessionReplacesItNotDuplicates() throws {
        _ = try call("POST", "/sessions", body: sessionJSON(pole: "208125"))
        _ = try call("POST", "/sessions", body: sessionJSON(pole: "5814901"))     // edited pole id
        XCTAssertTrue(TestSupport.wait { self.server.receivedSessions.count == 1 })
        XCTAssertEqual(server.receivedSessions.first?.poleId, "5814901")
    }

    func testDifferentSessionsAreKeptSeparately() throws {
        _ = try call("POST", "/sessions", body: sessionJSON(id: "AAAAAAAA-0000-0000-0000-000000000001"))
        _ = try call("POST", "/sessions", body: sessionJSON(id: "AAAAAAAA-0000-0000-0000-000000000002"))
        XCTAssertTrue(TestSupport.wait { self.server.receivedSessions.count == 2 })
    }

    /// End to end: save a capture -> technician syncs -> the mock SAP server has it.
    func testEndToEndAppToMockServer() throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir)
        let sync = SyncService(store: store,
                               connectivity: ConnectivityMonitor(simulatedConnected: true),
                               baseURL: URL(string: base)!,
                               defaults: TestSupport.isolatedDefaults())
        let workflow = WorkflowViewModel(store: store, sync: sync)

        workflow.startNew()
        workflow.poleIDCaptured(poleID: "5814901", confidence: .manual, photoData: nil)
        workflow.streetLightCaptured(serial: "E5000531", confidence: .high, photoData: nil)
        workflow.addAnotherStreetLight()
        workflow.streetLightCaptured(serial: "E5000532", confidence: .manual, photoData: nil)
        workflow.saveSession()
        XCTAssertTrue(server.receivedSessions.isEmpty, "saving alone does not upload")
        workflow.syncCurrent()

        XCTAssertTrue(TestSupport.wait(timeout: 8) { self.server.receivedSessions.count == 1 },
                      "server should have received the capture")
        let received = try XCTUnwrap(server.receivedSessions.first)
        XCTAssertEqual(received.poleId, "5814901")
        XCTAssertEqual(received.poleConfidence, "manual")
        XCTAssertEqual(received.streetLights.map(\.serialNumber), ["E5000531", "E5000532"])
        XCTAssertEqual(received.streetLights.map(\.confidence), ["high", "manual"])
        XCTAssertTrue(TestSupport.wait { store.sessions.first?.syncStatus == .synced })
    }

    /// The photo files really reach the server, byte for byte, and the record points at them.
    func testEndToEndPhotosArriveAtMockServer() throws {
        let dir = TestSupport.tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir)
        let sync = SyncService(store: store,
                               connectivity: ConnectivityMonitor(simulatedConnected: true),
                               baseURL: URL(string: base)!,
                               defaults: TestSupport.isolatedDefaults())
        let workflow = WorkflowViewModel(store: store, sync: sync)

        let poleJPEG = Data([0xFF, 0xD8, 0x0D, 0x0A, 0x0D, 0x0A, 0x80, 0xFF, 0xD9])
        let lightJPEG = Data([0xFF, 0xD8, 0xC3, 0x28, 0xFF, 0xD9])
        workflow.startNew()
        workflow.poleIDCaptured(poleID: "5814901", confidence: .high, photoData: poleJPEG)
        workflow.streetLightCaptured(serial: "E5000531", confidence: .high, photoData: lightJPEG)
        workflow.saveSession()
        workflow.syncCurrent()

        XCTAssertTrue(TestSupport.wait(timeout: 8) { self.server.receivedSessions.count == 1 })
        let received = try XCTUnwrap(server.receivedSessions.first)
        XCTAssertEqual(server.photo(named: try XCTUnwrap(received.polePhotoPath)), poleJPEG)
        XCTAssertEqual(server.photo(named: try XCTUnwrap(received.streetLights[0].photoPath)), lightJPEG)
    }
}
