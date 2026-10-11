import Foundation
import Combine
import UIKit

// MARK: - Confidence Threshold
// Scans at or above this value auto-capture; below it require manual confirmation.
let kHighConfidenceThreshold: Float = 0.80

// A value must be read identically this many times in a row before it counts as
// high confidence. Stops a single lucky misread from triggering auto-capture.
let kRequiredStableReads = 3
// Reads further apart than this (seconds) do not count as "in a row".
let kStableReadWindow: TimeInterval = 1.0

// MARK: - Capture ViewModel
// Shared base for both Pole ID and Street Light capture screens.

final class CaptureViewModel: ObservableObject {

    // MARK: Published

    @Published var detectedValue = ""
    @Published var confidence: Float = 0
    @Published var isHighConfidence = false
    @Published var isStabilising = false      // confident read, waiting for repeat confirmations
    @Published var showManualEntry = false
    @Published var manualEntryText = ""
    @Published var capturedPhotoData: Data?
    @Published var autoCaptured = false
    @Published var isCapturing = false    // "flash" animation while auto-capturing

    // MARK: Dependencies

    let camera: CameraManager

    // MARK: Private

    private var cancellables = Set<AnyCancellable>()
    private var didAutoCapture = false
    private var manualLocked = false          // technician-entered value must not be overwritten
    private var streakValue = ""
    private var streakCount = 0
    private var lastReadAt = Date.distantPast

    // MARK: Init

    /// - Parameter camera: tests pass an unconfigured `CameraManager` so no real camera starts.
    init(mode: CameraManager.ScanMode, camera: CameraManager? = nil) {
        if let camera {
            self.camera = camera
        } else {
            self.camera = CameraManager()
            self.camera.configure(mode: mode)
        }

        // Observe real-time scan results
        self.camera.$latestResult
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] result in
                self?.handle(result: result)
            }
            .store(in: &cancellables)

        // Receive captured photo
        self.camera.onPhotoCaptured = { [weak self] data in
            DispatchQueue.main.async {
                self?.capturedPhotoData = data
                self?.isCapturing = false
                self?.autoCaptured = true
            }
        }
    }

    // MARK: Scan Handling

    private func handle(result: ScanResult) {
        guard !manualLocked else { return }

        detectedValue = result.value
        confidence = result.confidence

        // Wrong-format or low-confidence reads reset the streak and need verification.
        let confident = result.isValidFormat && result.confidence >= kHighConfidenceThreshold
        let now = Date()
        if confident {
            let consecutive = result.value == streakValue
                && now.timeIntervalSince(lastReadAt) <= kStableReadWindow
            streakCount = consecutive ? streakCount + 1 : 1
            streakValue = result.value
            lastReadAt = now
        } else {
            streakCount = 0
            streakValue = ""
        }

        isHighConfidence = confident && streakCount >= kRequiredStableReads
        isStabilising = confident && !isHighConfidence

        // Auto-capture only once per session, and never while the manual sheet is open
        if isHighConfidence && !didAutoCapture && capturedPhotoData == nil && !showManualEntry {
            didAutoCapture = true
            isCapturing = true
            if !camera.capturePhoto() {          // no camera available: allow another attempt
                isCapturing = false
                didAutoCapture = false
            }
        }
    }

    // MARK: Manual Flow

    /// Opens the verify/update sheet, pre-filled with whatever was detected.
    func beginManualEntry() {
        manualEntryText = detectedValue
        showManualEntry = true
    }

    /// Shutter button: a photo is only taken directly when the read is already high confidence;
    /// otherwise the technician must verify the value first.
    func shutterTapped() {
        if isHighConfidence {
            camera.capturePhoto()
        } else {
            beginManualEntry()
        }
    }

    /// Called when technician taps "Verify / Update" with low confidence.
    func confirmManual() {
        guard !manualEntryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        manualLocked = true
        isStabilising = false
        detectedValue = manualEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        confidence = 0
        isHighConfidence = false
        showManualEntry = false
        // Capture photo manually after confirmation
        if capturedPhotoData == nil {
            isCapturing = true
            if !camera.capturePhoto() { isCapturing = false }
        }
    }

    /// The final value — either from scan or manual entry.
    var finalValue: String { detectedValue }

    /// The effective confidence for storage.
    var effectiveConfidence: Confidence {
        if capturedPhotoData != nil && !isHighConfidence { return .manual }
        return isHighConfidence ? .high : .low
    }

    // MARK: Cleanup

    func stop() {
        camera.stop()
    }
}
