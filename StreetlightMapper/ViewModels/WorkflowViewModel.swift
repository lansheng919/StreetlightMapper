import Foundation
import Combine

/// Drives the multi-step workflow: capture pole → capture ≥1 street lights → review → submit.
final class WorkflowViewModel: ObservableObject {

    enum Step {
        case capturePoloID
        case captureStreetLight
        case review
    }

    // MARK: Published

    @Published var currentStep: Step = .capturePoloID
    @Published var session: CaptureSession?
    @Published var isSaved = false

    // MARK: Dependencies

    private let store: SessionStore
    private let sync: SyncService
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    init(store: SessionStore, sync: SyncService) {
        self.store = store
        self.sync = sync
    }

    // MARK: Step: Pole ID captured

    func poleIDCaptured(poleID: String, confidence: Confidence, photoData: Data?) {
        var photoPath: String?
        if let data = photoData {
            let name = "pole_\(UUID().uuidString).jpg"
            photoPath = store.savePhoto(data, name: name)
        }
        let newSession = CaptureSession(poleID: poleID,
                                        poleConfidence: confidence,
                                        polePhotoPath: photoPath)
        session = newSession
        currentStep = .captureStreetLight
    }

    // MARK: Step: Street light captured

    func streetLightCaptured(serial: String, confidence: Confidence, photoData: Data?) {
        guard var s = session else { return }
        var photoPath: String?
        if let data = photoData {
            let name = "sl_\(UUID().uuidString).jpg"
            photoPath = store.savePhoto(data, name: name)
        }
        let entry = StreetLightEntry(sessionID: s.id,
                                     serialNumber: serial,
                                     confidence: confidence,
                                     photoPath: photoPath)
        s.addStreetLight(entry)
        session = s
        currentStep = .review
    }

    /// Technician wants to add another street light to this pole.
    func addAnotherStreetLight() {
        currentStep = .captureStreetLight
    }

    // MARK: Save & submit

    func saveSession() {
        guard let s = session else { return }
        store.addSession(s)
        isSaved = true
        sync.syncAll()
    }

    // MARK: Reset (start new workflow)

    func reset() {
        session = nil
        isSaved = false
        currentStep = .capturePoloID
    }
}
