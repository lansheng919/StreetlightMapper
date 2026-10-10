import SwiftUI
import AVFoundation

// MARK: - Camera Preview (UIViewRepresentable wrapping AVCaptureVideoPreviewLayer)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

// MARK: - Scan Overlay

/// Full-screen camera with a centred reticle and confidence badge.
struct ScanOverlayView: View {

    let detectedValue: String
    let confidence: Float
    let isHighConfidence: Bool
    let isStabilising: Bool                  // confident read, waiting for repeat confirmations
    let isCapturing: Bool
    let prompt: String                       // e.g. "Point at Pole ID label"

    var body: some View {
        ZStack {
            // Reticle frame
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 3)
                .frame(width: 280, height: 160)
                .shadow(color: borderColor.opacity(0.6), radius: 8)

            // Corner tick marks
            ReticleCorners(color: borderColor)
                .frame(width: 280, height: 160)

            // Capture flash
            if isCapturing {
                Color.white.opacity(0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.25), value: isCapturing)
            }

            // Status text sits just below the reticle, clear of the shutter button.
            Group {
                if !detectedValue.isEmpty {
                    VStack(spacing: 4) {
                        Text(detectedValue)
                            .font(.system(.headline, design: .monospaced))
                            .foregroundColor(badgeTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(badgeTextColor)
                                .frame(width: 8, height: 8)
                            Text(confidenceLabel)
                                .font(.caption)
                                .foregroundColor(badgeTextColor)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(badgeBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Text(prompt)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                }
            }
            .offset(y: 125)
        }
    }

    // MARK: Helpers

    private var borderColor: Color {
        if detectedValue.isEmpty { return .white }
        return isHighConfidence ? .green : .yellow
    }

    private var badgeTextColor: Color {
        isHighConfidence ? .green : .yellow
    }

    private var badgeBg: Color {
        Color.black.opacity(0.65)
    }

    private var confidenceLabel: String {
        let pct = Int(confidence * 100)
        if isHighConfidence { return "✓ \(pct)% confidence" }
        if isStabilising { return "Hold steady… \(pct)%" }
        return "⚠ \(pct)% – verify required"
    }
}

// MARK: - Reticle Corners

private struct ReticleCorners: View {
    let color: Color
    let len: CGFloat = 20
    let width: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                // Top-left
                p.move(to: CGPoint(x: 0, y: len))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: len, y: 0))
                // Top-right
                p.move(to: CGPoint(x: w - len, y: 0))
                p.addLine(to: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w, y: len))
                // Bottom-right
                p.move(to: CGPoint(x: w, y: h - len))
                p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: w - len, y: h))
                // Bottom-left
                p.move(to: CGPoint(x: len, y: h))
                p.addLine(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: 0, y: h - len))
            }
            .stroke(color, lineWidth: width)
        }
    }
}
