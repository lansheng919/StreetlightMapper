import AVFoundation
import Vision
import UIKit
import Combine

// MARK: - Scan Result

struct ScanResult {
    let value: String
    let confidence: Float   // 0…1
    let type: ScanType
    /// False when the value does not match the expected format (e.g. not a 5–10 digit Pole ID).
    /// Such results are shown for the technician to verify but never auto-captured.
    var isValidFormat: Bool = true
}

enum ScanType {
    case ocrText   // Pole ID label
    case qrCode    // Street light serial number
}

// MARK: - Camera Manager
// Drives the AVCaptureSession and publishes scan results.

final class CameraManager: NSObject, ObservableObject {

    // MARK: Published

    @Published var latestResult: ScanResult?
    @Published var isRunning = false
    @Published var permissionDenied = false

    // MARK: Internal

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var processingQueue = DispatchQueue(label: "com.slmapper.camera", qos: .userInitiated)
    private var scanMode: ScanMode = .ocr

    // Throttle Vision requests to ~5 fps
    private var lastAnalysis = Date.distantPast
    private let analysisInterval: TimeInterval = 0.2

    // Callbacks
    var onPhotoCaptured: ((Data) -> Void)?

    // MARK: Scan Mode

    enum ScanMode {
        case ocr    // Pole ID label
        case qr     // QR code
    }

    // MARK: Setup

    func configure(mode: ScanMode) {
        self.scanMode = mode
        checkPermission()
    }

    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.setupSession() } else { self?.permissionDenied = true }
                }
            }
        default:
            DispatchQueue.main.async { self.permissionDenied = true }
        }
    }

    private func setupSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720

        // Input
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        // Video output for real-time analysis
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Photo output for capture
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()

        processingQueue.async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async { self?.isRunning = true }
        }
    }

    // MARK: Photo Capture

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: Stop

    func stop() {
        if captureSession.isRunning {
            processingQueue.async { [weak self] in
                self?.captureSession.stopRunning()
                DispatchQueue.main.async { self?.isRunning = false }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        let now = Date()
        guard now.timeIntervalSince(lastAnalysis) >= analysisInterval else { return }
        lastAnalysis = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        switch scanMode {
        case .ocr:
            runOCR(on: pixelBuffer)
        case .qr:
            runQRDetection(on: pixelBuffer)
        }
    }

    // MARK: OCR (Pole ID)

    private func runOCR(on pixelBuffer: CVPixelBuffer) {
        let request = VNRecognizeTextRequest { [weak self] req, _ in
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }

            let lines: [OCRLine] = observations.compactMap { obs in
                guard let top = obs.topCandidates(1).first else { return nil }
                return OCRLine(text: top.string, confidence: top.confidence, box: obs.boundingBox)
            }

            let result: ScanResult
            if let id = PoleIDExtractor.extract(from: lines) {
                // Valid 5–10 digit Pole ID (horizontal or stacked digits)
                result = ScanResult(value: id.value, confidence: id.confidence, type: .ocrText)
            } else if let guess = PoleIDExtractor.suggestion(from: lines) {
                // Digits seen but not a valid ID: show for verification, never auto-capture
                result = ScanResult(value: guess, confidence: 0, type: .ocrText, isValidFormat: false)
            } else {
                return
            }
            DispatchQueue.main.async { self?.latestResult = result }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        // Back-camera buffers are landscape; the app is portrait-only, so rotate upright.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
    }

    // MARK: QR Code (Street Light)

    private func runQRDetection(on pixelBuffer: CVPixelBuffer) {
        let request = VNDetectBarcodesRequest { [weak self] req, _ in
            guard let observations = req.results as? [VNBarcodeObservation] else { return }

            let qrCodes = observations.filter { $0.symbology == .qr || $0.symbology == .code128 }
            guard let top = qrCodes.sorted(by: { $0.confidence > $1.confidence }).first,
                  let payload = top.payloadStringValue, !payload.isEmpty else { return }

            let result = ScanResult(
                value: payload.trimmingCharacters(in: .whitespacesAndNewlines),
                confidence: top.confidence,
                type: .qrCode
            )
            DispatchQueue.main.async { self?.latestResult = result }
        }
        request.symbologies = [.qr, .code128, .dataMatrix]

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        DispatchQueue.main.async { self.onPhotoCaptured?(data) }
    }
}
