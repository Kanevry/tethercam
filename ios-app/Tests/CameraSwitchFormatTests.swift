import XCTest
@testable import TetherCam

/// GitLab #11: the "did the lens swap change the format?" decision must be
/// made from the format snapshot the engine takes on its own sessionQueue,
/// not from a snapshot UsbServer read on its queue before the swap. These
/// tests pin the pure decision the engine now owns.
final class CameraSwitchFormatTests: XCTestCase {

    private typealias F = (width: UInt16, height: UInt16, fps: UInt16)
    private let fhd: F = (1920, 1080, 30)
    private let uhd: F = (3840, 2160, 30)

    /// The bug: two quick swaps wide -> ultra-wide (4K) -> tele (1080p). A
    /// stale `before` read on UsbServer.queue before the first swap completed
    /// still says 1080p, so the second swap looks "unchanged" although the
    /// session just ran 4K and the encoder would keep expecting 4K buffers.
    /// With the engine's own sequential snapshot the second comparison is
    /// 4K -> 1080p: changed, encoder restarted.
    func testStaleBeforeSnapshotWouldWronglySkipEncoderRestart() {
        // First swap, snapshot taken on sessionQueue: 1080p -> 4K.
        XCTAssertTrue(CaptureEngine.formatChanged(before: fhd, after: uhd))
        // Second swap, correct snapshot (what the previous swap left behind).
        XCTAssertTrue(CaptureEngine.formatChanged(before: uhd, after: fhd))
        // The stale snapshot from UsbServer.queue would have said "kept".
        XCTAssertFalse(CaptureEngine.formatChanged(before: fhd, after: fhd),
                       "sanity: the stale comparison is what hid the bug")
    }

    func testSameFormatKeepsTheEncoder() {
        XCTAssertFalse(CaptureEngine.formatChanged(before: fhd, after: fhd))
    }

    func testAnySingleDimensionCountsAsChanged() {
        XCTAssertTrue(CaptureEngine.formatChanged(before: fhd, after: (1280, 1080, 30)))
        XCTAssertTrue(CaptureEngine.formatChanged(before: fhd, after: (1920, 720, 30)))
        XCTAssertTrue(CaptureEngine.formatChanged(before: fhd, after: (1920, 1080, 60)))
    }

    func testNoPreviousFormatRestartsTheEncoder() {
        XCTAssertTrue(CaptureEngine.formatChanged(before: nil, after: fhd))
    }
}
