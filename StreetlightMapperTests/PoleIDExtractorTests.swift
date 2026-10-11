import XCTest
import CoreGraphics
@testable import StreetlightMapper

final class PoleIDExtractorTests: XCTestCase {

    // MARK: helpers

    private func line(_ text: String, _ conf: Float = 1.0,
                      x: CGFloat = 0.5, y: CGFloat = 0.5, w: CGFloat = 0.3, h: CGFloat = 0.05) -> OCRLine {
        OCRLine(text: text, confidence: conf, box: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h))
    }

    /// One digit per line, stacked top to bottom in a single column.
    private func stacked(_ digits: String, conf: Float = 1.0) -> [OCRLine] {
        digits.enumerated().map { i, ch in
            line(String(ch), conf, x: 0.5, y: 0.9 - CGFloat(i) * 0.08, w: 0.05, h: 0.06)
        }
    }

    // MARK: format validation (5–10 digits)

    func testValidLengths() {
        XCTAssertTrue(PoleIDExtractor.isValid("12345"))        // 5
        XCTAssertTrue(PoleIDExtractor.isValid("208125"))       // 6
        XCTAssertTrue(PoleIDExtractor.isValid("5814901"))      // 7
        XCTAssertTrue(PoleIDExtractor.isValid("1234567890"))   // 10
    }

    func testInvalidLengths() {
        XCTAssertFalse(PoleIDExtractor.isValid(""))
        XCTAssertFalse(PoleIDExtractor.isValid("1234"))        // 4
        XCTAssertFalse(PoleIDExtractor.isValid("12345678901")) // 11
    }

    func testInvalidCharacters() {
        XCTAssertFalse(PoleIDExtractor.isValid("12A456"))
        XCTAssertFalse(PoleIDExtractor.isValid("123-456"))
        XCTAssertFalse(PoleIDExtractor.isValid("123 456"))
        XCTAssertFalse(PoleIDExtractor.isValid("٢٠٨١٢٥"), "non-ASCII digits are not accepted")
    }

    // MARK: horizontal labels

    func testExtractsSingleLineId() {
        let r = PoleIDExtractor.extract(from: [line("208125", 0.95)])
        XCTAssertEqual(r?.value, "208125")
        XCTAssertEqual(r?.confidence, 0.95)
    }

    func testIgnoresSpacesInsideId() {
        XCTAssertEqual(PoleIDExtractor.extract(from: [line("208 125")])?.value, "208125")
    }

    func testRejectsTooShortRead() {
        XCTAssertNil(PoleIDExtractor.extract(from: [line("3123", 1.0)]),
                     "the blurry-plate misread must never be accepted")
    }

    func testPicksValidIdOverOtherLabelText() {
        let lines = [line("DANGER", 1.0), line("HIGH VOLTAGE", 1.0), line("208125", 0.9), line("2024", 1.0)]
        XCTAssertEqual(PoleIDExtractor.extract(from: lines)?.value, "208125")
    }

    func testPicksHighestConfidenceAmongValidIds() {
        let lines = [line("111111", 0.6), line("222222", 0.9)]
        XCTAssertEqual(PoleIDExtractor.extract(from: lines)?.value, "222222")
    }

    func testNoLinesGivesNil() {
        XCTAssertNil(PoleIDExtractor.extract(from: []))
    }

    func testLettersOnlyGivesNil() {
        XCTAssertNil(PoleIDExtractor.extract(from: [line("SERIAL NO", 1.0)]))
    }

    // MARK: stacked digits

    func testStackedDigitsAreAssembledTopToBottom() {
        let r = PoleIDExtractor.extract(from: stacked("5814901"))
        XCTAssertEqual(r?.value, "5814901")
    }

    func testStackedReadIsCappedBelowAutoCaptureThreshold() {
        let r = PoleIDExtractor.extract(from: stacked("5814901", conf: 1.0))
        XCTAssertNotNil(r)
        XCTAssertLessThan(r!.confidence, kHighConfidenceThreshold,
                          "stacked reads must always go to manual verification")
    }

    func testStackedNeedsAtLeastFiveDigits() {
        XCTAssertNil(PoleIDExtractor.extract(from: stacked("5814")))
    }

    func testStackedIgnoresDigitsOutsideTheColumn() {
        var lines = stacked("58149")
        lines.append(line("7", 1.0, x: 0.9, y: 0.5, w: 0.05, h: 0.06))   // stray digit far to the right
        XCTAssertEqual(PoleIDExtractor.extract(from: lines)?.value, "58149")
    }

    // MARK: suggestion for manual entry

    func testSuggestionKeepsDigitsOnly() {
        XCTAssertEqual(PoleIDExtractor.suggestion(from: [line("ID: 3123")]), "3123")
    }

    func testSuggestionNeedsThreeDigits() {
        XCTAssertNil(PoleIDExtractor.suggestion(from: [line("12")]))
    }

    func testSuggestionPrefersLongestRun() {
        XCTAssertEqual(PoleIDExtractor.suggestion(from: [line("123"), line("98765")]), "98765")
    }
}
