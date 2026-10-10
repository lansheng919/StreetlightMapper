import Foundation
import Vision
import ImageIO

// Runs the app's real scan pipeline (Vision settings + PoleIDExtractor) on still images.
// Usage:
//   swiftc -O tools/VisionProbe/main.swift StreetlightMapper/Services/PoleIDExtractor.swift -o /tmp/VisionProbe
//   /tmp/VisionProbe samples/*
// Expected value is taken from the file name, after the " - ".

func load(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func ocrLines(_ img: CGImage) -> [OCRLine] {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate          // same as CameraManager
    req.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: img, orientation: .up, options: [:]).perform([req])
    return (req.results ?? []).compactMap { obs in
        obs.topCandidates(1).first.map { OCRLine(text: $0.string, confidence: $0.confidence, box: obs.boundingBox) }
    }
}

func barcodes(_ img: CGImage) -> [(String, Float)] {
    let req = VNDetectBarcodesRequest()
    req.symbologies = [.qr, .code128, .dataMatrix]   // same as CameraManager
    try? VNImageRequestHandler(cgImage: img, orientation: .up, options: [:]).perform([req])
    return (req.results ?? []).compactMap { o in o.payloadStringValue.map { ($0, o.confidence) } }
}

var failures = 0
for path in CommandLine.arguments.dropFirst() {
    let name = (path as NSString).lastPathComponent
    let stem = (name as NSString).deletingPathExtension
    let expected = stem.components(separatedBy: " - ").last ?? ""
    guard let img = load(path) else { print("\(name): cannot load"); failures += 1; continue }

    let outcome: String   // what the app would do
    let value: String
    if name.hasPrefix("StreetLight") {
        let top = barcodes(img).max { $0.1 < $1.1 }
        value = top?.0 ?? "(nothing)"
        outcome = (top.map { $0.1 >= 0.80 } ?? false) ? "AUTO-CAPTURE" : "MANUAL VERIFY"
    } else {
        let lines = ocrLines(img)
        if let id = PoleIDExtractor.extract(from: lines) {
            value = id.value
            outcome = id.confidence >= 0.80 ? "AUTO-CAPTURE" : "MANUAL VERIFY"
        } else {
            value = PoleIDExtractor.suggestion(from: lines).map { "\($0) (rejected: invalid)" } ?? "(nothing)"
            outcome = "MANUAL VERIFY"
        }
    }

    // Pass = right value auto-captured, OR wrong/unreadable value routed to manual verify.
    let correct = value == expected
    let safe = correct ? outcome == "AUTO-CAPTURE" : outcome == "MANUAL VERIFY"
    if !safe { failures += 1 }
    print("\(safe ? "PASS" : "FAIL")  \(name)")
    print("      expected \(expected) | read \(value) | \(outcome)\(correct ? "" : "  (wrong read, routed safely)")")
}
exit(failures == 0 ? 0 : 1)
