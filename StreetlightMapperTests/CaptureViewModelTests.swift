import XCTest
import Combine
@testable import StreetlightMapper

// Tests the rules from the requirements: high confidence -> green + auto-capture,
// low confidence -> technician must verify before the photo is saved.

final class CaptureViewModelTests: XCTestCase {

    private var camera: CameraManager!
    private var vm: CaptureViewModel!

    override func setUp() {
        super.setUp()
        camera = CameraManager()               // never configured, so no real camera or permission prompt
        vm = CaptureViewModel(mode: .ocr, camera: camera)
    }

    private func scan(_ value: String, _ conf: Float, valid: Bool = true, type: ScanType = .ocrText) {
        camera.latestResult = ScanResult(value: value, confidence: conf, type: type, isValidFormat: valid)
        // handle(result:) is delivered on the main run loop
        let spin = expectation(description: "main queue")
        DispatchQueue.main.async { spin.fulfill() }
        wait(for: [spin], timeout: 1)
    }

    // MARK: stability (needs 3 identical confident reads)

    func testSingleConfidentReadIsNotYetHighConfidence() {
        scan("208125", 0.99)
        XCTAssertFalse(vm.isHighConfidence)
        XCTAssertTrue(vm.isStabilising)
        XCTAssertEqual(vm.detectedValue, "208125")
    }

    func testThreeIdenticalReadsBecomeHighConfidence() {
        for _ in 0..<kRequiredStableReads { scan("208125", 0.99) }
        XCTAssertTrue(vm.isHighConfidence)
        XCTAssertFalse(vm.isStabilising)
    }

    func testDifferentValueResetsTheStreak() {
        scan("208125", 0.99)
        scan("208125", 0.99)
        scan("208126", 0.99)                   // one flickering digit
        XCTAssertFalse(vm.isHighConfidence)
        scan("208126", 0.99)
        XCTAssertFalse(vm.isHighConfidence)
        scan("208126", 0.99)
        XCTAssertTrue(vm.isHighConfidence)
    }

    func testReadsSeparatedByTooLongDoNotCount() {
        scan("208125", 0.99)
        scan("208125", 0.99)
        Thread.sleep(forTimeInterval: kStableReadWindow + 0.2)
        scan("208125", 0.99)
        XCTAssertFalse(vm.isHighConfidence, "a gap longer than the window restarts the streak")
    }

    // MARK: low confidence / wrong format

    func testLowConfidenceNeverBecomesHigh() {
        for _ in 0..<5 { scan("208125", 0.79) }
        XCTAssertFalse(vm.isHighConfidence)
        XCTAssertFalse(vm.isStabilising)
    }

    func testConfidenceExactlyAtThresholdCounts() {
        for _ in 0..<kRequiredStableReads { scan("208125", kHighConfidenceThreshold) }
        XCTAssertTrue(vm.isHighConfidence)
    }

    func testInvalidFormatIsShownButNeverHigh() {
        for _ in 0..<5 { scan("3123", 1.0, valid: false) }
        XCTAssertEqual(vm.detectedValue, "3123", "shown so the technician can verify it")
        XCTAssertFalse(vm.isHighConfidence)
        XCTAssertFalse(vm.isStabilising)
    }

    func testLowReadInTheMiddleBreaksTheStreak() {
        scan("208125", 0.99)
        scan("208125", 0.99)
        scan("208125", 0.5)
        scan("208125", 0.99)
        XCTAssertFalse(vm.isHighConfidence)
    }

    // MARK: shutter + manual flow

    func testShutterOpensVerifySheetWhenNotHighConfidence() {
        scan("208125", 0.5)
        vm.shutterTapped()
        XCTAssertTrue(vm.showManualEntry)
    }

    func testBeginManualEntryPrefillsDetectedValue() {
        scan("3123", 1.0, valid: false)
        vm.beginManualEntry()
        XCTAssertEqual(vm.manualEntryText, "3123")
        XCTAssertTrue(vm.showManualEntry)
    }

    func testConfirmManualMarksValueAsManual() {
        scan("3123", 1.0, valid: false)
        vm.manualEntryText = " 208125 "
        vm.confirmManual()
        XCTAssertEqual(vm.finalValue, "208125", "value is trimmed")
        XCTAssertFalse(vm.showManualEntry)
        XCTAssertFalse(vm.isHighConfidence)
    }

    func testConfirmManualWithBlankTextDoesNothing() {
        scan("3123", 1.0, valid: false)
        vm.manualEntryText = "   "
        vm.confirmManual()
        XCTAssertEqual(vm.finalValue, "3123")
    }

    func testManualValueIsNotOverwrittenByLaterScans() {
        vm.manualEntryText = "999999"
        vm.confirmManual()
        for _ in 0..<5 { scan("111111", 1.0) }
        XCTAssertEqual(vm.finalValue, "999999")
        XCTAssertFalse(vm.isHighConfidence)
    }

    func testEffectiveConfidenceIsManualAfterPhotoWithManualValue() {
        vm.manualEntryText = "208125"
        vm.confirmManual()
        vm.capturedPhotoData = Data([1])
        XCTAssertEqual(vm.effectiveConfidence, .manual)
    }

    func testAutoCaptureWithNoCameraDoesNotGetStuck() {
        // The unit-test camera has no video connection, so the photo cannot be taken.
        for _ in 0..<kRequiredStableReads { scan("208125", 0.99) }
        XCTAssertTrue(vm.isHighConfidence)
        XCTAssertFalse(vm.isCapturing, "capture flash must not stay on when no photo was started")
        XCTAssertNil(vm.capturedPhotoData)
        XCTAssertFalse(vm.autoCaptured)
    }

    func testPhotoArrivalCompletesTheCapture() {
        for _ in 0..<kRequiredStableReads { scan("208125", 0.99) }
        camera.onPhotoCaptured?(Data([9, 9]))
        let spin = expectation(description: "main queue")
        DispatchQueue.main.async { spin.fulfill() }
        wait(for: [spin], timeout: 1)
        XCTAssertEqual(vm.capturedPhotoData, Data([9, 9]))
        XCTAssertTrue(vm.autoCaptured, "tells the screen to move on to the next step")
        XCTAssertFalse(vm.isCapturing)
    }

    func testEffectiveConfidenceIsHighAfterAutoRead() {
        for _ in 0..<kRequiredStableReads { scan("208125", 0.99) }
        XCTAssertEqual(vm.effectiveConfidence, .high)
    }
}
