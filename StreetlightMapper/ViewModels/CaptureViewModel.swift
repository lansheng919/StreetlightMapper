import Foundation
import Combine
import UIKit

// MARK: - Confidence Threshold
// Scans at or above this value auto-capture; below it require manual confirmation.
let kHighConfidenceThreshold: Float = 0.80

// MARK: - Capture ViewModel
// Shared base for both Pole ID and Street Light capture screens.

final class CaptureViewModel: ObservableObject {

    // MARK: Published

    @Published var detectedValue = ""
    @Published var confidence: Float = 0
    @Published var isHighConfidence = false
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

    // MARK: Init

    init(mode: CameraManager.ScanMode) {
        camera = CameraManager()
        camera.configure(mode: mode)

        // Observe real-time scan results
        camera.$latestResult
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] result in
                self?.handle(result: result)
            }
            .store(in: &cancellables)

        // Receive captured photo
        camera.onPhotoCaptured = { [weak self] data in
            DispatchQueue.main.async {
                self?.capturedPhotoData = data
                self?.isCapturing = false
                self?.autoCaptured = true
            }
        }
    }

    // MARK: Scan Handling

    private func handle(result: ScanResult) {
        detectedValue = result.value
        confidence = result.confidence
        isHighConfidence = result.confidence >= kHighConfidenceThreshold

        // Auto-capture only once per session
        if isHighConfidence && !didAutoCapture && capturedPhotoData == nil {
            didAutoCapture = true
            isCapturing = true
            camera.capturePhoto()
        }
    }

    // MARK: Manual Flow

    /// Called when technician taps "Verify / Update" with low confidence.
    func confirmManual() {
        guard !manualEntryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        detectedValue = manualEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        confidence = 0
        isHighConfidence = false
        showManualEntry = false
        // Capture photo manually after confirmation
        if capturedPhotoData == nil {
            isCapturing = true
            camera.capturePhoto()
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
