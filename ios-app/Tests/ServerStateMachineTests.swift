import XCTest
@testable import TetherCam

final class ServerStateMachineTests: XCTestCase {

    private let cams = [
        CameraDescriptor(id: 0, position: .back, name: "Rueck-Weitwinkel"),
        CameraDescriptor(id: 1, position: .front, name: "Front"),
    ]

    private func makeMachine() -> ServerStateMachine {
        ServerStateMachine(deviceName: "TestPhone", appVersion: "1.0", cameras: cams)
    }

    private let start = StartParams(cameraId: 0, width: 1920, height: 1080,
                                    fps: 30, bitrateKbps: 12000)

    func testHelloIsSentOnAccept() {
        var m = makeMachine()
        let a = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        guard case let .send(msg, to) = a.first, to == 1,
              case let .hello(v, name, app, cameras) = msg else {
            return XCTFail("expected HELLO, got \(a)")
        }
        XCTAssertEqual(v, Iucm.version)
        XCTAssertEqual(name, "TestPhone")
        XCTAssertEqual(app, "1.0")
        XCTAssertEqual(cameras, cams)
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(m.phase, .greeted)
    }

    func testStartOnlyAfterHelloPhase() {
        var m = makeMachine()
        // No connection yet: START is ignored, no capture is started.
        XCTAssertTrue(m.handle(.message(.start(start), nowUs: 0)).isEmpty)
        XCTAssertFalse(m.isStreaming)

        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        let a = m.handle(.message(.start(start), nowUs: 1))
        XCTAssertEqual(a, [.startCapture(start)])
        XCTAssertTrue(m.isStreaming)
        XCTAssertEqual(m.phase, .streaming(start))
    }

    func testUnknownCameraIdRejected() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        let bad = StartParams(cameraId: 9, width: 1920, height: 1080, fps: 30, bitrateKbps: 1)
        let a = m.handle(.message(.start(bad), nowUs: 1))
        guard case let .send(.error(code, _), _) = a.first else { return XCTFail("\(a)") }
        XCTAssertEqual(code, IucmErrorCode.formatUnsupported.rawValue)
        XCTAssertFalse(m.isStreaming)
    }

    func testSecondConnectionGetsBusyAndIsClosed() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        let a = m.handle(.connectionAccepted(id: 2, nowUs: 10))
        guard case let .send(.error(code, _), to) = a.first else { return XCTFail("\(a)") }
        XCTAssertEqual(code, IucmErrorCode.busy.rawValue)
        XCTAssertEqual(to, 2)
        XCTAssertEqual(a.last, .close(id: 2))
        XCTAssertEqual(m.activeConnection, 1, "the first connection stays active")
    }

    func testPingIsEchoedAsPong() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        let a = m.handle(.message(.ping(timestampUs: 0xDEADBEEF), nowUs: 500))
        XCTAssertEqual(a, [.send(.pong(timestampUs: 0xDEADBEEF), to: 1)])
        XCTAssertEqual(m.lastPingUs, 500)
    }

    func testPingTimeoutFreesTheListener() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 1_000_000))
        _ = m.handle(.message(.start(start), nowUs: 1_000_000))

        // 5.9 s without PING: still alive.
        XCTAssertTrue(m.handle(.tick(nowUs: 6_900_000)).isEmpty)
        XCTAssertEqual(m.activeConnection, 1)

        // 6.0 s: stop capture and close, so a new receiver is not stuck on BUSY.
        let a = m.handle(.tick(nowUs: 7_000_000))
        XCTAssertEqual(a, [.stopCapture, .close(id: 1)])
        XCTAssertNil(m.activeConnection)
        XCTAssertEqual(m.phase, .idle)

        // The freed listener accepts the next receiver with a fresh HELLO.
        let b = m.handle(.connectionAccepted(id: 2, nowUs: 8_000_000))
        guard case .send(.hello, 2) = b.first else { return XCTFail("\(b)") }
    }

    func testPingResetsTheTimeoutWindow() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        _ = m.handle(.message(.ping(timestampUs: 1), nowUs: 5_000_000))
        XCTAssertTrue(m.handle(.tick(nowUs: 10_000_000)).isEmpty)
        XCTAssertEqual(m.activeConnection, 1)
    }

    func testStopStopsCaptureButKeepsConnection() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        _ = m.handle(.message(.start(start), nowUs: 0))
        XCTAssertEqual(m.handle(.message(.stop, nowUs: 1)), [.stopCapture])
        XCTAssertEqual(m.phase, .greeted)
        XCTAssertEqual(m.activeConnection, 1)
        // A second STOP is a no-op.
        XCTAssertTrue(m.handle(.message(.stop, nowUs: 2)).isEmpty)
    }

    func testRestartWithNewParamsStopsFirst() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        _ = m.handle(.message(.start(start), nowUs: 0))
        let next = StartParams(cameraId: 1, width: 1280, height: 720, fps: 60, bitrateKbps: 6000)
        XCTAssertEqual(m.handle(.message(.start(next), nowUs: 1)),
                       [.stopCapture, .startCapture(next)])
    }

    func testConnectionCloseStopsCaptureAndFreesListener() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        _ = m.handle(.message(.start(start), nowUs: 0))
        XCTAssertEqual(m.handle(.connectionClosed(id: 1)), [.stopCapture])
        XCTAssertNil(m.activeConnection)
        XCTAssertEqual(m.phase, .idle)
    }

    func testCloseOfStaleConnectionIdIsIgnored() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        XCTAssertTrue(m.handle(.connectionClosed(id: 99)).isEmpty)
        XCTAssertEqual(m.activeConnection, 1)
    }

    func testCameraDeniedIsReportedAsError() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        _ = m.handle(.message(.start(start), nowUs: 0))
        let a = m.handle(.captureFailed(.cameraDenied, text: "denied"))
        XCTAssertEqual(a.first, .stopCapture)
        guard case let .send(.error(code, _), 1) = a.last else { return XCTFail("\(a)") }
        XCTAssertEqual(code, IucmErrorCode.cameraDenied.rawValue)
        XCTAssertEqual(m.phase, .greeted, "the listener stays open after a capture failure")
    }

    func testTickWithoutConnectionDoesNothing() {
        var m = makeMachine()
        XCTAssertTrue(m.handle(.tick(nowUs: 999_999_999)).isEmpty)
    }
}
