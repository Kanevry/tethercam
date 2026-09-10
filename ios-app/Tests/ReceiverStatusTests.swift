import XCTest
@testable import TetherCam

/// The bug: the app said "Connected to OBS" and offered an OBS audio footnote no
/// matter who was on the cable, so someone running the TetherCam Mac app was told
/// about a receiver they do not have and about audio the Mac app cannot carry
/// (GitLab #19). The status text is now picked from CLIENT_INFO.
final class ReceiverStatusTests: XCTestCase {

    func testMacAppReceiverIsNotCalledObs() {
        let info = ReceiverInfo(kind: .macApp, name: "TetherCam for Mac", version: "0.3.0")
        let (key, name) = ReceiverStatus.connected(for: info)
        XCTAssertEqual(key, "status.connected.macApp")
        XCTAssertNil(name)
    }

    func testObsPluginReceiverSaysObs() {
        let info = ReceiverInfo(kind: .obsPlugin, name: "TetherCam OBS plugin", version: "0.3.0")
        XCTAssertEqual(ReceiverStatus.connected(for: info).key, "status.connected.obs")
    }

    /// A 1.0/1.1 receiver never sends CLIENT_INFO: no claim about which one it is.
    func testUnidentifiedReceiverIsGeneric() {
        let (key, name) = ReceiverStatus.connected(for: nil)
        XCTAssertEqual(key, "status.connected.generic")
        XCTAssertNil(name)
    }

    func testToolReceiverIsNamedVerbatim() {
        let info = ReceiverInfo(kind: .tool, name: "usbcam-recv", version: "0.3.0")
        let (key, name) = ReceiverStatus.connected(for: info)
        XCTAssertEqual(key, "status.connected.named")
        XCTAssertEqual(name, "usbcam-recv")
    }

    /// An unknown kind with no name would render "Connected to " — fall back.
    func testUnknownKindWithoutNameFallsBackToGeneric() {
        let info = ReceiverInfo(kind: 99, name: "  ", version: "")
        XCTAssertEqual(ReceiverStatus.connected(for: info).key, "status.connected.generic")
    }

    func testAudioFootnoteDoesNotPromiseAudioToTheMacApp() {
        let mac = ReceiverInfo(kind: .macApp, name: "TetherCam for Mac", version: "0.3.0")
        XCTAssertEqual(ReceiverStatus.audioFootnoteKey(for: mac),
                       "settings.audioFootnote.macApp")
        XCTAssertEqual(ReceiverStatus.audioFootnoteKey(for: nil),
                       "settings.audioFootnote.obs")
        let obs = ReceiverInfo(kind: .obsPlugin, name: "plugin", version: "0.3.0")
        XCTAssertEqual(ReceiverStatus.audioFootnoteKey(for: obs),
                       "settings.audioFootnote.obs")
    }

    func testDiagnosticsValue() {
        XCTAssertEqual(ReceiverStatus.diagnosticsValue(for: nil), "\u{2014}")
        let info = ReceiverInfo(kind: .macApp, name: "TetherCam for Mac", version: "0.3.0")
        XCTAssertEqual(ReceiverStatus.diagnosticsValue(for: info),
                       "TetherCam for Mac 0.3.0")
    }
}

/// The bug: a second receiver was refused with ERROR 1 BUSY on the wire, but the
/// phone's screen said nothing, so the person looking at the phone had no way to
/// learn why the Mac stayed black (GitLab #19). The rejection is now counted and
/// the counter travels into the UI stats.
final class BusyRejectionTests: XCTestCase {

    private let cams = [CameraDescriptor(id: 0, position: .back, name: "Back Wide")]

    func testSecondConnectionIsCountedAsABusyRejection() {
        var m = ServerStateMachine(deviceName: "TestPhone", appVersion: "1.0", cameras: cams)
        XCTAssertEqual(m.busyRejections, 0)
        _ = m.handle(.connectionAccepted(id: 1, nowUs: 0))
        XCTAssertEqual(m.busyRejections, 0, "the first receiver is not a rejection")

        let actions = m.handle(.connectionAccepted(id: 2, nowUs: 1_000))
        XCTAssertEqual(m.busyRejections, 1)
        XCTAssertTrue(actions.contains { action in
            if case let .send(msg, to) = action, to == 2,
               case let .error(code, _) = msg {
                return code == IucmErrorCode.busy.rawValue
            }
            return false
        }, "the refusal is still ERROR 1 BUSY on the wire")

        _ = m.handle(.connectionAccepted(id: 3, nowUs: 2_000))
        XCTAssertEqual(m.busyRejections, 2, "every attempt counts, so the hint re-arms")
        XCTAssertEqual(m.activeConnection, 1, "the running take is untouched")
    }
}
