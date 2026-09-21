import Foundation
import Combine

// MARK: - Sync Service
// Sends pending sessions to the configured SAP / external REST endpoint.
// Falls back gracefully when offline.

final class SyncService: ObservableObject {

    // MARK: Published

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncMessage = ""

    // MARK: Dependencies

    private let store: SessionStore
    private let connectivity: ConnectivityMonitor
    private var cancellables = Set<AnyCancellable>()

    // MARK: Configuration
    // Change sapBaseURL to point at a real SAP endpoint.
    // While no live SAP is available the MockSAPServer (running locally) is used.

    private var sapBaseURL: URL {
        // First try environment override (useful for CI / testing)
        if let override = ProcessInfo.processInfo.environment["SAP_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        // Default: mock server listening on the same device
        return URL(string: "http://localhost:8080/api/v1")!
    }

    // MARK: Init

    init(store: SessionStore, connectivity: ConnectivityMonitor) {
        self.store = store
        self.connectivity = connectivity

        // Auto-sync when connectivity is restored
        connectivity.$isConnected
            .filter { $0 }
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncAll() }
            .store(in: &cancellables)
    }

    // MARK: Public

    func syncAll() {
        let pending = store.pendingSessions()
        guard !pending.isEmpty else { return }
        guard connectivity.isConnected else {
            lastSyncMessage = "Offline — \(pending.count) session(s) queued"
            return
        }

        isSyncing = true
        lastSyncMessage = "Syncing \(pending.count) session(s)…"

        let group = DispatchGroup()
        var successCount = 0
        var failCount = 0

        for session in pending {
            group.enter()
            uploadSession(session) { success in
                if success { successCount += 1 } else { failCount += 1 }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isSyncing = false
            var parts: [String] = []
            if successCount > 0 { parts.append("\(successCount) synced") }
            if failCount > 0 { parts.append("\(failCount) failed") }
            self?.lastSyncMessage = parts.joined(separator: ", ")
        }
    }

    // MARK: Private

    private func uploadSession(_ session: CaptureSession, completion: @escaping (Bool) -> Void) {
        var updated = session
        updated.syncStatus = .syncing
        store.updateSession(updated)

        let dto = store.dto(for: session)
        let url = sapBaseURL.appendingPathComponent("sessions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(dto)
        } catch {
            markFailed(session)
            completion(false)
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    var synced = session
                    synced.markSynced()
                    self?.store.updateSession(synced)
                    completion(true)
                } else {
                    self?.markFailed(session)
                    completion(false)
                }
            }
        }.resume()
    }

    private func markFailed(_ session: CaptureSession) {
        var failed = session
        failed.syncStatus = .failed
        store.updateSession(failed)
    }
}
