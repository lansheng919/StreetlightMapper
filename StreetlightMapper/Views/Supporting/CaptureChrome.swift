import SwiftUI

// MARK: - Close button used on the full-screen capture screens

struct CloseCaptureButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
        }
        .accessibilityLabel("Close camera")
    }
}

// MARK: - Shown when the user has denied camera access

struct CameraPermissionDeniedView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.secondary)
                Text("Camera access is off")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Text("StreetlightMapper needs the camera to scan Pole ID labels and street light QR codes. Turn it on in Settings.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 32)

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(ActionButtonStyle(color: .blue))
                .padding(.horizontal, 40)

                Button("Back", action: onClose)
                    .foregroundColor(.white)
            }
        }
    }
}
