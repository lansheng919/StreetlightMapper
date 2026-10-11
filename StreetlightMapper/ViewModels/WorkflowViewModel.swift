import Foundation
import Combine

/// Drives the multi-step workflow: capture pole → capture ≥1 street lights → review → submit.
/// Also handles resuming an unfinished capture and editing an already-saved one.
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
    /// True while the full-screen capture flow is presented.
    @Published var isActive = false
    /// True when `session` is a copy of an already-saved session being edited.
    @Published private(set) var isEditingExisting = false

    /// An unfinished capture the technician can resume or discard.
    var hasDraft: Bool { session != nil && !isSaved }

    /// The stored copy of the session being reviewed (nil for a brand-new capture not yet saved).
    var storedSession: CaptureSession? {
        session.flatMap { store.session(id: $0.id) }
    }

    /// A saved capture that has never reached the server can be deleted from the phone.
    var canDeleteCurrent: Bool { storedSession?.canDelete ?? false }

    // MARK: Dependencies

    private let store: SessionStore
    private let sync: SyncService
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    init(store: SessionStore, sync: SyncService) {
        self.store = store
        self.sync = sync
    }

    // MARK: Entering / leaving the flow

    /// Starts a fresh capture, discarding any draft.
    func startNew() {
        discardDraft()
        isActive = true
    }

    /// Re-opens the unfinished capture where the technician left off.
    func resume() {
        guard session != nil else { return startNew() }
        isActive = true
    }

    /// Opens a saved session in the review screen for editing.
    func edit(_ saved: CaptureSession) {
        session = saved
        isSaved = false
        isEditingExisting = true
        currentStep = .review
        isActive = true
    }

    /// Closes the flow but keeps the draft so it can be resumed.
    func exit() {
        isActive = false
    }

    /// Throws the current draft away.
    func discardDraft() {
        session = nil
        isSaved = false
        isEditingExisting = false
        currentStep = .capturePoloID
    }

    /// Called once the full-screen flow has been dismissed. A finished or edited-existing
    /// session is cleared; only an unfinished new capture stays as a resumable draft.
    func cleanupAfterDismiss() {
        if isSaved || isEditingExisting { discardDraft() }
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

    // MARK: Editing

    /// Corrects the Pole ID by hand; the capture is then marked as manually entered.
    func updatePoleID(_ value: String) {
        guard var s = session, value != s.poleID else { return }
        s.poleID = value
        s.poleConfidence = .manual
        s.updatedAt = Date()
        session = s
    }

    /// Corrects one street light serial number by hand.
    func updateSerial(lightID: UUID, value: String) {
        guard var s = session,
              let idx = s.streetLights.firstIndex(where: { $0.id == lightID }),
              s.streetLights[idx].serialNumber != value else { return }
        s.streetLights[idx].serialNumber = value
        s.streetLights[idx].confidence = .manual
        s.updatedAt = Date()
        session = s
    }

    func deleteStreetLights(at offsets: IndexSet) {
        guard var s = session else { return }
        s.streetLights.remove(atOffsets: offsets)
        s.updatedAt = Date()
        session = s
    }

    // MARK: Save

    /// Saves to the local database (new or edited). It is NOT uploaded here: the technician
    /// syncs later, from Home / History, or straight away with `syncCurrent()`.
    func saveSession() {
        guard var s = session, !s.streetLights.isEmpty else { return }
        s.syncStatus = .pending
        s.updatedAt = Date()
        if isEditingExisting {
            store.updateSession(s)
        } else {
            store.addSession(s)
        }
        session = s
        isSaved = true
    }

    /// Uploads the capture that was just saved.
    func syncCurrent() {
        guard let s = session else { return }
        sync.sync(sessionID: s.id)
    }

    // MARK: Delete

    /// Deletes the capture under review from the phone, including its photos.
    /// Refused once the server has received it, because the server would keep an orphan copy.
    @discardableResult
    func deleteCurrent() -> Bool {
        guard let stored = storedSession else {
            // never saved: this is just discarding the draft
            discardDraft()
            isActive = false
            return true
        }
        guard stored.canDelete else { return false }
        store.deleteSession(id: stored.id)
        discardDraft()
        isActive = false
        return true
    }
}
