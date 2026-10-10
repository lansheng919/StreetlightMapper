import CoreGraphics
import Foundation

// MARK: - OCR line (decoupled from Vision so it can be tested on still images)

struct OCRLine {
    let text: String
    let confidence: Float
    let box: CGRect          // Vision normalised coordinates, origin bottom-left
}

// MARK: - Pole ID Extractor
// Accepts only numeric Pole IDs of 5–10 digits. Anything else is rejected, so a
// confident-but-wrong OCR read of unrelated text can never be auto-captured.

enum PoleIDExtractor {

    static let digitRange = 5...10

    /// Stacked-digit reads are capped below the auto-capture threshold. Vision often drops or
    /// misreads digits in vertical labels while still reporting 100% confidence, and a wrong ID
    /// of valid length would otherwise be auto-captured. They go to manual verification instead.
    static let stackedMaxConfidence: Float = 0.5

    static func isValid(_ value: String) -> Bool {
        digitRange.contains(value.count) && value.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Best valid Pole ID found in the OCR output, or nil if none.
    static func extract(from lines: [OCRLine]) -> (value: String, confidence: Float)? {
        var found: [(value: String, confidence: Float)] = []

        // Horizontal labels: one OCR line holds the whole ID (spaces ignored).
        for line in lines {
            let compact = line.text.filter { !$0.isWhitespace }
            if isValid(compact) { found.append((compact, line.confidence)) }
        }

        // Vertical labels: one digit per line, stacked top to bottom.
        if let stacked = stackedDigits(in: lines) { found.append(stacked) }

        return found.max { $0.confidence < $1.confidence }
    }

    /// Digits-only guess (3+ digits) used to pre-fill manual verification when no valid ID was found.
    static func suggestion(from lines: [OCRLine]) -> String? {
        lines
            .map { $0.text.filter { $0.isASCII && $0.isNumber } }
            .filter { $0.count >= 3 }
            .max { $0.count < $1.count }
    }

    // MARK: Stacked digits

    private static func stackedDigits(in lines: [OCRLine]) -> (value: String, confidence: Float)? {
        let singles = lines.filter { line in
            let t = line.text.filter { !$0.isWhitespace }
            return t.count == 1 && t.allSatisfy { $0.isASCII && $0.isNumber }
        }
        guard singles.count >= digitRange.lowerBound else { return nil }

        // Keep the digits that share one vertical column (around the median x).
        let medianX = singles.map { $0.box.midX }.sorted()[singles.count / 2]
        let medianWidth = singles.map { $0.box.width }.sorted()[singles.count / 2]
        let tolerance = max(0.02, medianWidth)

        let column = singles
            .filter { abs($0.box.midX - medianX) <= tolerance }
            .sorted { $0.box.midY > $1.box.midY }          // top of image first

        let value = column.map { $0.text.filter { !$0.isWhitespace } }.joined()
        guard isValid(value) else { return nil }
        return (value, min(stackedMaxConfidence, column.map { $0.confidence }.min() ?? 0))
    }
}
