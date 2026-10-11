import Foundation
import Combine

// MARK: - Session Store
// Single source of truth.  Persists to JSON in the app's Documents directory.
// In a production app this would be backed by CoreData or SQLite; JSON is used
// here so that the code compiles and runs without any additional dependencies.

final class SessionStore: ObservableObject {

    // MARK: Published

    @Published private(set) var sessions: [CaptureSession] = []

    // MARK: Private

    private let baseDir: URL
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Init

    /// - Parameter directory: storage folder; defaults to the app's Documents directory.
    ///   Tests pass a temporary folder.
    init(directory: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.baseDir = directory ?? docs
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        self.fileURL = baseDir.appendingPathComponent("sessions.json")
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    // MARK: Public API

    func addSession(_ session: CaptureSession) {
        sessions.append(session)
        save()
    }

    func updateSession(_ session: CaptureSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx] = session
        save()
    }

    /// Removes a session and the photos stored for it.
    func deleteSession(id: UUID) {
        if let s = sessions.first(where: { $0.id == id }) { deletePhotos(of: s) }
        sessions.removeAll { $0.id == id }
        save()
    }

    /// Deletes the pole and street-light photo files of a session from disk.
    func deletePhotos(of session: CaptureSession) {
        let paths = [session.polePotoPath].compactMap { $0 } + session.streetLights.compactMap { $0.photoPath }
        for path in paths {
            try? FileManager.default.removeItem(at: baseDir.appendingPathComponent(path))
        }
    }

    func session(id: UUID) -> CaptureSession? {
        sessions.first { $0.id == id }
    }

    /// Returns sessions that have not been successfully synced yet.
    func pendingSessions() -> [CaptureSession] {
        sessions.filter { $0.needsSync }
    }

    // MARK: Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              var decoded = try? decoder.decode([CaptureSession].self, from: data)
        else { return }
        // An upload interrupted by the app closing leaves "syncing" behind; treat it as failed
        // so it can be retried or deleted.
        for i in decoded.indices where decoded[i].syncStatus == .syncing {
            decoded[i].syncStatus = .failed
        }
        // Captures synced by an older version have no timestamp; they still reached the server.
        for i in decoded.indices where decoded[i].syncStatus == .synced && decoded[i].lastSyncedAt == nil {
            decoded[i].lastSyncedAt = decoded[i].updatedAt
        }
        sessions = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Photo Storage

    /// Saves a JPEG image to the Documents/photos directory and returns the relative path.
    func savePhoto(_ data: Data, name: String) -> String? {
        let photosDir = baseDir.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        let url = photosDir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return "photos/\(name)"
        } catch {
            return nil
        }
    }

    /// Resolves a relative photo path to a full URL.
    func photoURL(relativePath: String) -> URL? {
        baseDir.appendingPathComponent(relativePath)
    }

    // MARK: DTO conversion

    func dto(for session: CaptureSession) -> SessionDTO {
        let fmt = ISO8601DateFormatter()
        return SessionDTO(
            sessionId: session.id.uuidString,
            poleId: session.poleID,
            poleConfidence: session.poleConfidence.rawValue,
            polePotoPath: session.polePotoPath,
            streetLights: session.streetLights.map { sl in
                StreetLightDTO(
                    id: sl.id.uuidString,
                    serialNumber: sl.serialNumber,
                    confidence: sl.confidence.rawValue,
                    photoPath: sl.photoPath,
                    capturedAt: fmt.string(from: sl.capturedAt)
                )
            },
            createdAt: fmt.string(from: session.createdAt),
            syncStatus: session.syncStatus.rawValue
        )
    }
}
