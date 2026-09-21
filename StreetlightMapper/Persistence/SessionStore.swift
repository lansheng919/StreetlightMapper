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

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Init

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.fileURL = docs.appendingPathComponent("sessions.json")
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

    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    /// Returns sessions that have not been successfully synced yet.
    func pendingSessions() -> [CaptureSession] {
        sessions.filter { $0.syncStatus == .pending || $0.syncStatus == .failed }
    }

    // MARK: Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([CaptureSession].self, from: data)
        else { return }
        sessions = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Photo Storage

    /// Saves a JPEG image to the Documents/photos directory and returns the relative path.
    func savePhoto(_ data: Data, name: String) -> String? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let photosDir = docs.appendingPathComponent("photos", isDirectory: true)
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
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(relativePath)
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
