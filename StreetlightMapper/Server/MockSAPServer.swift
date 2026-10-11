import Foundation
import Combine
import Network

// MARK: - Mock SAP Server
// A lightweight HTTP server embedded in the app that:
//   • Accepts POST /api/v1/sessions — stores the session JSON, returns 201
//   • Accepts GET  /api/v1/sessions — lists all received sessions
//   • Accepts GET  /api/v1/sessions/:id — fetches a single session
//   • Accepts GET  /api/v1/health — returns { "status": "ok" }
//
// This allows end-to-end testing without a live SAP environment.
// External tools (Postman, curl, SAP PI) can hit this server over the local network.

final class MockSAPServer: ObservableObject {

    // MARK: Published

    @Published private(set) var isRunning = false
    @Published private(set) var receivedSessions: [SessionDTO] = []
    @Published private(set) var port: UInt16 = 8080

    // MARK: Private

    private var listener: NWListener?
    private let serverQueue = DispatchQueue(label: "com.slmapper.mockserver", qos: .background)
    private let encoder = JSONEncoder()

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

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            guard let self = self, let data = data, !data.isEmpty else {
                if isComplete { connection.cancel() }
                return
            }

            guard let raw = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            self.route(raw: raw, connection: connection)
        }
    }

    // MARK: Routing

    private func route(raw: String, connection: NWConnection) {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { respond(connection, status: 400, body: "{}"); return }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { respond(connection, status: 400, body: "{}"); return }

        let method = parts[0]
        let path   = parts[1]

        // Extract body (after blank line)
        let bodyStart = raw.range(of: "\r\n\r\n")
        let body = bodyStart.map { String(raw[raw.index($0.upperBound, offsetBy: 0)...]) } ?? ""

        if path == "/api/v1/health" {
            respond(connection, status: 200, body: "{\"status\":\"ok\"}")

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
        let bodyData = body.data(using: .utf8)!
        let header = "HTTP/1.1 \(status) \(statusText(status))\r\n" +
                     "Content-Type: application/json\r\n" +
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
        case 422: return "Unprocessable Entity"
        default:  return "Internal Server Error"
        }
    }
}
