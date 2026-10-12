import Foundation
import Combine

// MARK: - Sync Service
// Sends pending sessions to the configured SAP / external REST endpoint.
// Falls back gracefully when offline.

final class SyncService: ObservableObject {

    // MARK: Published

    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncMessage = ""
    /// When on, queued captures upload by themselves once the network returns.
    /// Off by default: the technician decides when to sync.
    @Published var autoSyncEnabled: Bool {
        didSet { defaults.set(autoSyncEnabled, forKey: Self.autoSyncKey) }
    }

    static let autoSyncKey = "autoSyncEnabled"

    // MARK: Dependencies

    private let store: SessionStore
    private let connectivity: ConnectivityMonitor
    private let urlSession: URLSession
    private let baseURLOverride: URL?
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    // MARK: Configuration
    // Change sapBaseURL to point at a real SAP endpoint.
    // While no live SAP is available the MockSAPServer (running locally) is used.

    private var sapBaseURL: URL {
        if let baseURLOverride { return baseURLOverride }
        // First try environment override (useful for CI / testing)
        if let override = ProcessInfo.processInfo.environment["SAP_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        // Default: mock server listening on the same device
        return URL(string: "http://localhost:8080/api/v1")!
    }

    // MARK: Init

    init(store: SessionStore,
         connectivity: ConnectivityMonitor,
         baseURL: URL? = nil,
         urlSession: URLSession = .shared,
         defaults: UserDefaults = .standard) {
        self.store = store
        self.connectivity = connectivity
        self.baseURLOverride = baseURL
        self.urlSession = urlSession
        self.defaults = defaults
        self.autoSyncEnabled = defaults.bool(forKey: Self.autoSyncKey)

        // Optional auto-sync when connectivity is restored (off unless the technician turns it on)
        connectivity.$isConnected
            .filter { $0 }
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.autoSyncEnabled else { return }
                self.syncAll()
            }
            .store(in: &cancellables)
    }

    // MARK: Public

    /// Uploads every capture that has not been synced yet.
    func syncAll() {
        sync(store.pendingSessions())
    }

    /// Uploads one capture (no-op if it is already synced).
    func sync(sessionID: UUID) {
        guard let s = store.session(id: sessionID), s.needsSync else { return }
        sync([s])
    }

    private func sync(_ pending: [CaptureSession]) {
        guard !pending.isEmpty, !isSyncing else { return }
        guard connectivity.isConnected else {
            lastSyncMessage = "Offline. \(pending.count) capture(s) waiting. Sync when you have a connection."
            return
        }

        isSyncing = true
        lastSyncMessage = "Syncing \(pending.count) capture(s)…"

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
            if failCount > 0 { parts.append("\(failCount) failed. Try again later.") }
            self?.lastSyncMessage = parts.joined(separator: ", ")
        }
    }

    // MARK: Private

    /// Uploads a capture's photos first, then its record. The record is only sent once every
    /// photo has arrived, so the server never holds a record that points at missing images.
    private func uploadSession(_ session: CaptureSession, completion: @escaping (Bool) -> Void) {
        var updated = session
        updated.syncStatus = .syncing
        store.updateSession(updated)

        uploadPhotos(of: session) { [weak self] photosOK in
            guard let self else { return }
            guard photosOK else {
                self.markFailed(session)
                completion(false)
                return
            }
            self.postRecord(session, completion: completion)
        }
    }

    /// `PUT <base>/photos/<name>` with the raw JPEG bytes, one request per photo.
    /// Repeating a PUT just replaces the same file, so retries after a failure are safe.
    private func uploadPhotos(of session: CaptureSession, completion: @escaping (Bool) -> Void) {
        let paths = ([session.polePhotoPath] + session.streetLights.map { $0.photoPath }).compactMap { $0 }
        // A photo file that no longer exists on the phone cannot be sent; do not block the capture on it.
        let uploads: [(String, Data)] = paths.compactMap { path in
            guard let url = store.photoURL(relativePath: path),
                  let data = try? Data(contentsOf: url) else { return nil }
            return (path, data)
        }
        guard !uploads.isEmpty else { completion(true); return }

        let group = DispatchGroup()
        var allOK = true
        for (path, data) in uploads {
            group.enter()
            var request = URLRequest(url: sapBaseURL.appendingPathComponent(path))
            request.httpMethod = "PUT"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            urlSession.uploadTask(with: request, from: data) { _, response, _ in
                DispatchQueue.main.async {
                    let ok = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
                    if !ok { allOK = false }
                    group.leave()
                }
            }.resume()
        }
        group.notify(queue: .main) { completion(allOK) }
    }

    private func postRecord(_ session: CaptureSession, completion: @escaping (Bool) -> Void) {
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

        urlSession.dataTask(with: request) { [weak self] _, response, error in
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
