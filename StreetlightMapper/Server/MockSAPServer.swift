import Foundation
import Combine
import Network

// MARK: - Mock SAP Server
// A lightweight HTTP server embedded in the app that:
//   • Accepts POST /api/v1/sessions — stores the session JSON, returns 201
//   • Accepts GET  /api/v1/sessions — lists all received sessions
//   • Accepts GET  /api/v1/sessions/:id — fetches a single session
//   • Accepts PUT  /api/v1/photos/:name — stores a JPEG (raw bytes in the body), returns 201
//   • Accepts GET  /api/v1/photos/:name — returns a stored JPEG
//   • Accepts GET  /api/v1/health — returns { "status": "ok" }
//
// This allows end-to-end testing without a live SAP environment.
// External tools (Postman, curl, SAP PI) can hit this server over the local network.

final class MockSAPServer: ObservableObject {

    // MARK: Published

    @Published private(set) var isRunning = false
    @Published private(set) var receivedSessions: [SessionDTO] = []
    @Published private(set) var receivedPhotoCount = 0
    @Published private(set) var port: UInt16 = 8080

    // MARK: Private

    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "com.slmapper.mockserver", qos: .background)
    private let encoder = JSONEncoder()
    private let photoLock = NSLock()
    private var photos: [String: Data] = [:]      // "photos/<name>.jpg" -> JPEG bytes

    /// Forgets everything the mock server has received (it only lives in memory anyway).
    func clearReceived() {
        receivedSessions.removeAll()
        photoLock.lock(); photos.removeAll(); photoLock.unlock()
        receivedPhotoCount = 0
    }

    /// The stored photo for a relative path such as "photos/pole_x.jpg", if the server has it.
    func photo(named path: String) -> Data? {
        photoLock.lock(); defer { photoLock.unlock() }
        return photos[path]
    }

    // MARK: Start / Stop

    func start(port: UInt16 = 8080) {
        self.port = port
        let params = NWParameters.tcp
        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!) else { return }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }

        listener.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.isRunning = state == .ready
            }
        }

        listener.start(queue: serverQueue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async { self.isRunning = false }
    }

    // MARK: Connection Handling

    private func handle(connection: NWConnection) {
        connection.start(queue: serverQueue)
        receive(on: connection)
    }

    /// Reads until the whole request has arrived. Headers and body often come in separate
    /// TCP segments, so a single read can see a POST with an empty body.
    private func receive(on connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buffer = buffer
            if let data = data { buffer.append(data) }

            if self.isComplete(request: buffer) || isComplete || error != nil {
                guard !buffer.isEmpty else {
                    connection.cancel()
                    return
                }
                self.route(request: buffer, connection: connection)
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    /// True once the headers are in and the body is as long as Content-Length says.
    private func isComplete(request buffer: Data) -> Bool {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let headers = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
        var expected = 0
        for line in headers.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("content-length:") {
            expected = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return buffer.count - headerEnd.upperBound >= expected
    }

    // MARK: Routing

    private func route(request: Data, connection: NWConnection) {
        // Headers are text; the body stays raw bytes so a JPEG is not corrupted.
        guard let headerEnd = request.range(of: Data("\r\n\r\n".utf8)) else {
            respond(connection, status: 400, body: "{}"); return
        }
        let head = String(decoding: request[..<headerEnd.lowerBound], as: UTF8.self)
        let bodyData = request[headerEnd.upperBound...]
        let body = String(decoding: bodyData, as: UTF8.self)

        let parts = (head.components(separatedBy: "\r\n").first ?? "").components(separatedBy: " ")
        guard parts.count >= 2 else { respond(connection, status: 400, body: "{}"); return }

        let method = parts[0]
        let path   = parts[1]

        if path == "/api/v1/health" {
            if method == "GET" {
                respond(connection, status: 200, body: "{\"status\":\"ok\"}")
            } else {
                respond(connection, status: 405, body: "{\"error\":\"method not allowed\"}")
            }

        } else if method == "PUT" && path.hasPrefix("/api/v1/photos/") {
            let key = String(path.dropFirst("/api/v1/".count))        // "photos/<name>"
            guard !bodyData.isEmpty, !key.contains("..") else {
                respond(connection, status: 422, body: "{\"error\":\"empty or invalid photo\"}"); return
            }
            photoLock.lock(); photos[key] = Data(bodyData); let count = photos.count; photoLock.unlock()
            DispatchQueue.main.async { self.receivedPhotoCount = count }
            respond(connection, status: 201, body: "{\"accepted\":true}")

        } else if method == "GET" && path.hasPrefix("/api/v1/photos/") {
            let key = String(path.dropFirst("/api/v1/".count))
            if let data = photo(named: key) {
                respond(connection, status: 200, data: data, contentType: "image/jpeg")
            } else {
                respond(connection, status: 404, body: "{\"error\":\"not found\"}")
            }

        } else if method == "GET" && path == "/api/v1/sessions" {
            let json = (try? encoder.encode(receivedSessions)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            respond(connection, status: 200, body: json)

        } else if method == "GET" && path.hasPrefix("/api/v1/sessions/") {
            let id = String(path.dropFirst("/api/v1/sessions/".count))
            if let session = receivedSessions.first(where: { $0.sessionId == id }) {
                let json = (try? encoder.encode(session)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                respond(connection, status: 200, body: json)
            } else {
                respond(connection, status: 404, body: "{\"error\":\"not found\"}")
            }

        } else if method == "POST" && path == "/api/v1/sessions" {
            if let data = body.data(using: .utf8),
               let dto = try? JSONDecoder().decode(SessionDTO.self, from: data) {
                // Re-submitting an edited session replaces the earlier copy (upsert by sessionId)
                DispatchQueue.main.async {
                    if let i = self.receivedSessions.firstIndex(where: { $0.sessionId == dto.sessionId }) {
                        self.receivedSessions[i] = dto
                    } else {
                        self.receivedSessions.append(dto)
                    }
                }
                respond(connection, status: 201, body: "{\"accepted\":true}")
            } else {
                respond(connection, status: 422, body: "{\"error\":\"invalid body\"}")
            }

        } else {
            respond(connection, status: 404, body: "{\"error\":\"not found\"}")
        }
    }

    // MARK: HTTP Response

    private func respond(_ connection: NWConnection, status: Int, body: String) {
        respond(connection, status: status, data: Data(body.utf8), contentType: "application/json")
    }

    private func respond(_ connection: NWConnection, status: Int, data bodyData: Data, contentType: String) {
        let header = "HTTP/1.1 \(status) \(statusText(status))\r\n" +
                     "Content-Type: \(contentType)\r\n" +
                     "Content-Length: \(bodyData.count)\r\n" +
                     "Connection: close\r\n\r\n"
        var response = header.data(using: .utf8)!
        response.append(bodyData)

        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 422: return "Unprocessable Entity"
        default:  return "Internal Server Error"
        }
    }
}
