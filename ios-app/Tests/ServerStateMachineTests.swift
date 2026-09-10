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

    // MARK: - CLIENT_INFO, PROTOCOL.md 4.11

    func testClientInfoBeforeStartLatchesReceiverInfo() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        XCTAssertNil(m.receiverInfo)
        let info = ReceiverInfo(kind: .obsPlugin, name: "TetherCam OBS plugin", version: "0.2.1")
        // CLIENT_INFO produces no action of its own — it only identifies the peer.
        XCTAssertTrue(m.handle(.message(.clientInfo(info), nowUs: 1)).isEmpty)
        XCTAssertEqual(m.receiverInfo, info)
        XCTAssertEqual(m.phase, .greeted)

        // START still behaves exactly as before.
        let a = m.handle(.message(.start(start), nowUs: 2))
        XCTAssertEqual(a, [.startCapture(start)])
        XCTAssertEqual(m.receiverInfo, info)

        // A later CLIENT_INFO simply re-latches (4.11).
        let second = ReceiverInfo(kind: .macApp, name: "TetherCam for Mac", version: "0.3.0")
        XCTAssertTrue(m.handle(.message(.clientInfo(second), nowUs: 3)).isEmpty)
        XCTAssertEqual(m.receiverInfo, second)

        // The identity belongs to the connection, not to the app.
        _ = m.handle(.connectionClosed(id: 1))
        XCTAssertNil(m.receiverInfo)
    }

    /// A 1.1 receiver never sends CLIENT_INFO: the flow is unchanged and the app
    /// simply has no name to show.
    func testReceiverWithoutClientInfoLeavesInfoNil() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        var withAudio = start
        withAudio.wantsAudio = true
        XCTAssertEqual(m.handle(.message(.start(withAudio), nowUs: 1)), [.startCapture(withAudio)])
        XCTAssertNil(m.receiverInfo)
        XCTAssertTrue(m.isStreaming)
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

    func testPreferredCameraOverridesStartCamera() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        XCTAssertTrue(m.handle(.selectCamera(1)).isEmpty, "nothing is streaming yet")
        XCTAssertEqual(m.preferredCameraId, 1)

        // START asks for camera 0, the phone already said 1: format survives,
        // camera id does not.
        let a = m.handle(.message(.start(start), nowUs: 1))
        let expected = StartParams(cameraId: 1, width: 1920, height: 1080,
                                   fps: 30, bitrateKbps: 12000)
        XCTAssertEqual(a, [.startCapture(expected)])
        XCTAssertEqual(m.phase, .streaming(expected))
    }

    func testStartCameraIsHonoredWhileNoPreferenceIsSet() {
        var m = makeMachine()
        XCTAssertNil(m.preferredCameraId)
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        let next = StartParams(cameraId: 1, width: 1280, height: 720, fps: 60, bitrateKbps: 6000)
        XCTAssertEqual(m.handle(.message(.start(next), nowUs: 1)), [.startCapture(next)])
    }

    /// obs-iphone-usb-cam#4: a stop/start pair parks the session on the 720p
    /// preview between the two, and that preview buffer leaks a 720p CONFIG to
    /// the receiver. The lens swap must be its own action with the format kept.
    func testSelectCameraWhileStreamingSwitchesLensAndKeepsFormat() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        _ = m.handle(.message(.start(start), nowUs: 0))

        let a = m.handle(.selectCamera(1))
        let switched = StartParams(cameraId: 1, width: start.width, height: start.height,
                                   fps: start.fps, bitrateKbps: start.bitrateKbps)
        XCTAssertEqual(a, [.switchCamera(switched)],
                       "no stopCapture: the session must never drop to preview mid-take")
        XCTAssertFalse(a.contains(.stopCapture))
        guard case let .switchCamera(p)? = a.first else { return XCTFail("\(a)") }
        XCTAssertEqual(p.cameraId, 1)
        XCTAssertEqual(p.width, start.width)
        XCTAssertEqual(p.height, start.height)
        XCTAssertEqual(p.fps, start.fps)
        XCTAssertEqual(p.bitrateKbps, start.bitrateKbps)
        XCTAssertEqual(m.phase, .streaming(switched))

        // Picking the lens that is already live is a no-op — no stream hiccup.
        XCTAssertTrue(m.handle(.selectCamera(1)).isEmpty)
    }

    func testSelectingAnAbsentCameraLeavesStartInCharge() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        _ = m.handle(.message(.start(start), nowUs: 0))
        XCTAssertTrue(m.handle(.selectCamera(9)).isEmpty)
        XCTAssertNil(m.preferredCameraId)
        XCTAssertEqual(m.phase, .streaming(start))
    }

    /// The audio flag must survive the camera-preference rewrite in `handle`.
    /// Rebuilding `effective` field by field instead of copying START would drop
    /// it silently: the Mac asks for sound and gets a mute take with no error.
    func testStartWithAudioFlagReachesCaptureAsWantsAudio() {
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        var withAudio = start
        withAudio.wantsAudio = true
        // A phone-side preference is the case that rewrites the params.
        _ = m.handle(.selectCamera(1))
        let a = m.handle(.message(.start(withAudio), nowUs: 1))
        guard case let .startCapture(p) = a.last else { return XCTFail("expected startCapture, got \(a)") }
        XCTAssertTrue(p.wantsAudio)
        XCTAssertEqual(p.cameraId, 1)
    }

    /// An 11-byte START from a protocol-1.0 receiver has no flags byte, so it
    /// must never switch the microphone on.
    func testLegacyElevenByteStartAsksForNoAudio() throws {
        // Little-endian on the wire, see PROTOCOL.md section 2.
        var payload = Data([0])                                   // cameraId
        payload.append(contentsOf: [0x80, 0x07, 0x38, 0x04])      // 1920x1080
        payload.append(contentsOf: [30, 0])                       // 30 fps
        payload.append(contentsOf: [0xE0, 0x2E, 0, 0])            // 12000 kbps
        XCTAssertEqual(payload.count, 11)
        let msg = try IucmCodec.decodePayload(type: IucmType.start.rawValue,
                                              flags: 0, payload: payload)
        var m = makeMachine()
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        let a = m.handle(.message(msg, nowUs: 1))
        guard case let .startCapture(p) = a.last else { return XCTFail("expected startCapture, got \(a)") }
        XCTAssertFalse(p.wantsAudio)
        XCTAssertEqual(p.width, 1920)
        XCTAssertEqual(p.height, 1080)
    }

    func testTickWithoutConnectionDoesNothing() {
        var m = makeMachine()
        XCTAssertTrue(m.handle(.tick(nowUs: 999_999_999)).isEmpty)
    }
}
