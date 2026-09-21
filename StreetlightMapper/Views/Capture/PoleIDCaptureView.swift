import SwiftUI

// MARK: - Pole ID Capture Screen

struct PoleIDCaptureView: View {

    @StateObject private var vm = CaptureViewModel(mode: .ocr)
    @EnvironmentObject private var workflow: WorkflowViewModel

    @State private var showLowConfidenceAlert = false
    @State private var captureTriggered = false

    var body: some View {
        ZStack {
            // Full-screen camera
            CameraPreviewView(session: vm.camera.captureSession)
                .ignoresSafeArea()

            // Overlay
            ScanOverlayView(
                detectedValue: vm.detectedValue,
                confidence: vm.confidence,
                isHighConfidence: vm.isHighConfidence,
                isCapturing: vm.isCapturing,
                prompt: "Point at the Pole ID label"
            )

            // Top header
            VStack {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Pole ID Capture")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding(12)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .padding(.top, 12)
                Spacer()
            }

            // Bottom action strip
            VStack {
                Spacer()
                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }

            // Manual entry sheet
            if vm.showManualEntry {
                manualEntryOverlay
            }
        }
        .navigationBarHidden(true)
        // Watch for auto-capture completion
        .onChange(of: vm.autoCaptured) { captured in
            if captured { proceedToNextStep() }
        }
    }

    // MARK: Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if vm.capturedPhotoData == nil {
                // Show manual-entry prompt when confidence is low and value detected
                if !vm.detectedValue.isEmpty && !vm.isHighConfidence {
                    Button(action: { vm.showManualEntry = true }) {
                        Label("Verify / Update Pole ID", systemImage: "pencil.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle(color: .orange))
                }

                // Allow forced capture any time
                Button(action: { vm.camera.capturePhoto() }) {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: Manual Entry Overlay

    private var manualEntryOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Enter Pole ID")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Text("Detected: \"\(vm.detectedValue)\"")
                    .font(.caption)
                    .foregroundColor(.yellow)

                TextField("Pole ID", text: $vm.manualEntryText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(8)
                    .padding(.horizontal, 24)

                HStack(spacing: 16) {
                    Button("Cancel") { vm.showManualEntry = false }
                        .buttonStyle(ActionButtonStyle(color: .gray))

                    Button("Confirm & Capture") {
                        vm.confirmManual()
                    }
                    .buttonStyle(ActionButtonStyle(color: .blue))
                }
                .padding(.horizontal, 24)
            }
            .padding(.vertical, 32)
            .background(Color(white: 0.15))
            .cornerRadius(16)
            .padding(.horizontal, 20)
        }
    }

    // MARK: Navigation

    private func proceedToNextStep() {
        vm.stop()
        workflow.poleIDCaptured(
            poleID: vm.finalValue,
            confidence: vm.effectiveConfidence,
            photoData: vm.capturedPhotoData
        )
    }
}
