import XCTest
@testable import TetherCam

/// Double-tap lens cycling (GitLab #9): the pure list walk behind the gesture.
final class CameraCycleTests: XCTestCase {

    private let lenses: [CameraDescriptor] = [
        CameraDescriptor(id: 0, position: .back, name: "Back Wide"),
        CameraDescriptor(id: 1, position: .back, name: "Back Ultra Wide"),
        CameraDescriptor(id: 2, position: .back, name: "Back Telephoto"),
        CameraDescriptor(id: 3, position: .front, name: "Front"),
    ]

    func testWalksTheListInOrderAndWrapsAround() {
        XCTAssertEqual(CameraCycle.next(after: 0, in: lenses), 1)
        XCTAssertEqual(CameraCycle.next(after: 1, in: lenses), 2)
        XCTAssertEqual(CameraCycle.next(after: 2, in: lenses), 3)
        XCTAssertEqual(CameraCycle.next(after: 3, in: lenses), 0)
    }

    func testOrderIsTheListOrderNotTheIdOrder() {
        // Ids are not necessarily ascending; the list order is what the user sees.
        XCTAssertEqual(CameraCycle.next(after: 7, in: [7, 2, 9]), 2)
        XCTAssertEqual(CameraCycle.next(after: 2, in: [7, 2, 9]), 9)
        XCTAssertEqual(CameraCycle.next(after: 9, in: [7, 2, 9]), 7)
    }

    func testSingleCameraHasNothingToCycleTo() {
        XCTAssertNil(CameraCycle.next(after: 0, in: [lenses[0]]))
        XCTAssertNil(CameraCycle.next(after: 5, in: [UInt8(0)]))
    }

    func testEmptyListYieldsNil() {
        XCTAssertNil(CameraCycle.next(after: 0, in: [CameraDescriptor]()))
        XCTAssertNil(CameraCycle.next(after: 0, in: [UInt8]()))
    }

    func testUnknownCurrentStartsAtTheFirstEntry() {
        XCTAssertEqual(CameraCycle.next(after: 42, in: lenses), 0)
        XCTAssertEqual(CameraCycle.next(after: 1, in: [7, 2, 9]), 7)
    }
}
