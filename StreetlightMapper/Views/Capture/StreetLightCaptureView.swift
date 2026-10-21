import SwiftUI

// MARK: - Street Light QR Capture Screen

struct StreetLightCaptureView: View {

    @StateObject private var vm = CaptureViewModel(mode: .qr)
    @EnvironmentObject private var workflow: WorkflowViewModel

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
                isStabilising: vm.isStabilising,
                isCapturing: vm.isCapturing,
                prompt: "Point at street light QR code",
                showsPercentage: false,                 // a QR either decodes or it doesn't
                isRejected: vm.isRejected,
                rejectedLabel: "Serial already captured"
            )

            // Top header
            VStack {
                HStack(spacing: 10) {
                    CloseCaptureButton { workflow.exit() }

                    HStack {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Step 2 of 2 · Street light")
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        if let s = workflow.session {
                            Text("\(s.streetLights.count) captured")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
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

            if vm.camera.permissionDenied {
                CameraPermissionDeniedView { workflow.exit() }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            vm.rejectionMessage = "This serial number is already captured."
            vm.shouldReject = { serial in workflow.isDuplicateSerial(serial) }
        }
        .onDisappear { vm.stop() }
        .onChange(of: vm.autoCaptured) { captured in
            if captured { proceedAfterCapture() }
        }
    }

    // MARK: Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if vm.capturedPhotoData == nil {
                if (workflow.session?.streetLights.isEmpty == false) {
                    Button(action: { workflow.backToReview() }) {
                        Label("Back to Review", systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle(color: Color(white: 0.3)))
                }

                if !vm.detectedValue.isEmpty && !vm.isHighConfidence {
                    Button(action: { vm.beginManualEntry() }) {
                        Label("Verify / Update Serial Number", systemImage: "pencil.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ActionButtonStyle(color: .orange))
                }

                Button(action: { vm.shutterTapped() }) {
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
                Text("Enter Serial Number")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                if !vm.detectedValue.isEmpty {
                    Text("Detected: \"\(vm.detectedValue)\"")
                        .font(.caption)
                        .foregroundColor(.yellow)
                }

                TextField("Serial Number", text: $vm.manualEntryText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(8)
                    .padding(.horizontal, 24)

                if let error = vm.manualError {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                        .accessibilityIdentifier("capture.duplicateError")
                }

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

    private func proceedAfterCapture() {
        vm.stop()
        // Refused only if the serial turned out to be a duplicate; fall back to the review list.
        if !workflow.streetLightCaptured(
            serial: vm.finalValue,
            confidence: vm.effectiveConfidence,
            photoData: vm.capturedPhotoData
        ) {
            workflow.backToReview()
        }
    }
}
