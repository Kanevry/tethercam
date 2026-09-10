// SPDX-License-Identifier: MIT
import CoreMedia
import CoreVideo
import SystemExtensions
import XCTest
@testable import TetherCamCore

final class CameraTests: XCTestCase {
    // Bug guarded: parseState grabbing the first "[" or a foreign line, e.g.
    // returning OBS's state or the "(ver/build)" group instead of ours.
    func testParseStateReadsBracketedStateOfTetherCamLineOnly() {
        let listing = """
        1 extension(s)
        --- com.apple.system_extension.cmio
        enabled\tactive\tteamID\tbundleID (version)\tname\t[state]
        *\t*\t2MMRE5MTB8\tcom.obsproject.obs-studio.mac-camera-extension (32.2.2/31845296735)\tOBS Virtual Camera\t[activated waiting for user]
        *\t*\tG3QZ66475M\t\(TetherCamContract.extensionBundleID) (0.3.0/5)\tTetherCam Camera\t[activated enabled]
        """
        XCTAssertEqual(ExtensionInstaller.parseState(from: listing), "activated enabled")
    }

    func testParseStateWaitingForUserAndAbsent() {
        let waiting = "*\t\tG3QZ66475M\t\(TetherCamContract.extensionBundleID) (0.3.0/5)\tTetherCam Camera\t[activated waiting for user]"
        XCTAssertEqual(ExtensionInstaller.parseState(from: waiting), "activated waiting for user")

        let obsOnly = "*\t\t2MMRE5MTB8\tcom.obsproject.obs-studio.mac-camera-extension (32.2.2/31845296735)\tOBS Virtual Camera\t[activated waiting for user]"
        XCTAssertNil(ExtensionInstaller.parseState(from: obsOnly))
        XCTAssertNil(ExtensionInstaller.parseState(from: ""))
    }

    // Bug guarded: the enumeration path crashing or matching a wrong device
    // (this machine has no TetherCam extension installed).
    // Environment-aware: without the extension the real enumeration path must
    // report deviceNotFound; with the extension enabled (developer Mac) the
    // sink must connect and expose a queue (guards the nil-altered-proc bug:
    // CMIOStreamCopyBufferQueue returned noErr and no queue).
    func testSinkConnectMatchesExtensionPresence() throws {
        let sink = CMIOSink()
        if CMIOSink.isDevicePresent() {
            do {
                try sink.connect()
            } catch CMIOSinkError.osStatus(let code, let call) where call == "CMIODeviceStartStream" || call == "CMIOStreamCopyBufferQueue" {
                throw XCTSkip("sink held by another host process: \(call) status \(code)")
            }
            XCTAssertTrue(sink.isConnected)
            sink.disconnect()
            XCTAssertFalse(sink.isConnected)
        } else {
            XCTAssertThrowsError(try sink.connect()) { error in
                XCTAssertEqual(error as? CMIOSinkError, .deviceNotFound)
            }
            XCTAssertFalse(sink.isConnected)
        }
        XCTAssertEqual(sink.pushedFrames, 0)
    }

    // Bug guarded: pts scaled with the wrong timescale (ns vs us) or a
    // duration that does not match the contract's 30 fps.
    func testSampleBufferTimingFromNV12Buffer() throws {
        var pool: CVPixelBufferPool?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: TetherCamContract.pixelFormat,
            kCVPixelBufferWidthKey: TetherCamContract.width,
            kCVPixelBufferHeightKey: TetherCamContract.height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
        ]
        XCTAssertEqual(CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool), kCVReturnSuccess)
        var pixelBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(pool), &pixelBuffer), kCVReturnSuccess)

        var formatDescription: CMVideoFormatDescription?
        let sample = try CMIOSink.makeSampleBuffer(
            from: try XCTUnwrap(pixelBuffer), ptsUs: 1_000_000, formatDescription: &formatDescription)

        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        XCTAssertEqual(pts.value, 1_000_000)
        XCTAssertEqual(pts.timescale, 1_000_000)
        XCTAssertEqual(CMTimeGetSeconds(pts), 1.0, accuracy: 0.000_001)
        XCTAssertEqual(CMSampleBufferGetDuration(sample), CMTime(value: 1, timescale: 30))
        XCTAssertFalse(CMSampleBufferGetDecodeTimeStamp(sample).isValid)

        let fd = try XCTUnwrap(formatDescription)
        let dims = CMVideoFormatDescriptionGetDimensions(fd)
        XCTAssertEqual(dims.width, 1920)
        XCTAssertEqual(dims.height, 1080)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(fd), TetherCamContract.pixelFormat)

        // Same geometry: the format description is reused, not rebuilt.
        let second = try CMIOSink.makeSampleBuffer(
            from: try XCTUnwrap(pixelBuffer), ptsUs: 1_033_333, formatDescription: &formatDescription)
        XCTAssertTrue(try XCTUnwrap(formatDescription) === fd)
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(second).value, 1_033_333)
    }

    // Bug guarded: "enabled" without a visible device reported as ready.
    func testCameraStatusInterpretation() {
        XCTAssertEqual(CameraStatus.interpret(state: nil, devicePresent: false), .extensionMissing)
        XCTAssertEqual(CameraStatus.interpret(state: "activated waiting for user", devicePresent: false), .waitingForUser)
        XCTAssertEqual(CameraStatus.interpret(state: "activated enabled", devicePresent: true), .ready)
        if case .error = CameraStatus.interpret(state: "activated enabled", devicePresent: false) {} else {
            XCTFail("enabled without device must be an error")
        }
        if case .error = CameraStatus.interpret(state: "terminated waiting to uninstall on reboot", devicePresent: false) {} else {
            XCTFail("unknown state must be an error")
        }
    }
}

// #32: "activated enabled" without a camera device.
final class DevicePresenceWatcherTests: XCTestCase {
    // Bug guarded: the watcher declaring the device absent although it appeared
    // one poll later (the app would then offer a restart on a healthy install).
    func testDeviceAppearingWithinBudgetIsPresent() {
        let watcher = DevicePresenceWatcher(pollInterval: 1, budget: 10)
        var probes = 0
        var sleeps: [TimeInterval] = []
        let outcome = watcher.wait(isPresent: { probes += 1; return probes >= 3 },
                                   sleep: { sleeps.append($0) })
        XCTAssertEqual(outcome, .present)
        XCTAssertEqual(probes, 3)
        XCTAssertEqual(sleeps, [1, 1], "one sleep between two probes, none after the hit")
    }

    // Bug guarded: an immediately present device still waiting out the budget.
    func testDevicePresentOnFirstProbeDoesNotSleep() {
        let watcher = DevicePresenceWatcher(pollInterval: 1, budget: 10)
        var sleeps = 0
        XCTAssertEqual(watcher.wait(isPresent: { true }, sleep: { _ in sleeps += 1 }), .present)
        XCTAssertEqual(sleeps, 0)
    }

    // Bug guarded: a device that never appears reported as present (the #32
    // state would never be named), or the loop polling past the budget.
    func testDeviceNeverAppearingIsAbsentAfterBudget() {
        let watcher = DevicePresenceWatcher(pollInterval: 1, budget: 10)
        var probes = 0
        var slept: TimeInterval = 0
        let outcome = watcher.wait(isPresent: { probes += 1; return false }, sleep: { slept += $0 })
        XCTAssertEqual(outcome, .absent)
        XCTAssertEqual(probes, watcher.attempts)
        XCTAssertEqual(probes, 11, "one immediate probe plus one per second of the 10 s budget")
        XCTAssertEqual(slept, 10, accuracy: 0.001)
    }

    // Bug guarded: a degenerate configuration trapping instead of probing.
    // Without the clamp in init, pollInterval 0 makes budget/pollInterval
    // infinite and Int(.infinity) traps — the app would crash on the very path
    // that is supposed to diagnose a broken extension.
    func testDegenerateConfigurationStillProbesExactlyOnce() {
        let zeroInterval = DevicePresenceWatcher(pollInterval: 0, budget: 10)
        XCTAssertEqual(zeroInterval.pollInterval, 0.01)
        XCTAssertEqual(zeroInterval.attempts, 1001)

        let noBudget = DevicePresenceWatcher(pollInterval: 1, budget: -5)
        XCTAssertEqual(noBudget.budget, 0)
        XCTAssertEqual(noBudget.attempts, 1)
        var probes = 0
        var sleeps = 0
        XCTAssertEqual(noBudget.wait(isPresent: { probes += 1; return false }, sleep: { _ in sleeps += 1 }), .absent)
        XCTAssertEqual(probes, 1, "a zero budget still gets the immediate probe")
        XCTAssertEqual(sleeps, 0)
    }

    func testAsyncDriverReportsAbsentWithoutBlockingTooLong() async {
        let watcher = DevicePresenceWatcher(pollInterval: 0.01, budget: 0.03)
        let outcome = await watcher.waitForDevice(isPresent: { false })
        XCTAssertEqual(outcome, .absent)
        XCTAssertEqual(watcher.attempts, 4)
    }
}

// #25 item 5: a canceled macOS confirmation must not read as a finished request.
final class ExtensionRequestErrorTests: XCTestCase {
    // Bug guarded: OSSystemExtensionError.requestCanceled (code 11) mapped to a
    // failure — the caller then cannot restore the state the system still has,
    // and "Remove camera extension" would show "not installed" while the
    // extension keeps running.
    func testCanceledRequestIsItsOwnState() {
        let canceled = NSError(domain: OSSystemExtensionErrorDomain,
                               code: OSSystemExtensionError.Code.requestCanceled.rawValue)
        XCTAssertEqual(ExtensionInstaller.state(for: canceled), .canceled)
    }

    // Bug guarded: the domain check dropped from state(for:), so any error that
    // happens to carry code 11 (requestCanceled's raw value) reads as "user
    // canceled, nothing changed" — the app would then keep showing the old
    // state after a real activation failure.
    func testForeignErrorWithTheCanceledCodeIsNotCanceled() {
        let impostor = NSError(domain: NSPOSIXErrorDomain,
                               code: OSSystemExtensionError.Code.requestCanceled.rawValue)
        guard case .failed = ExtensionInstaller.state(for: impostor) else {
            return XCTFail("only the SystemExtensions domain may map to .canceled")
        }
    }

    func testOtherErrorsStayFailures() {
        let notInApplications = NSError(domain: OSSystemExtensionErrorDomain,
                                        code: OSSystemExtensionError.Code.unsupportedParentBundleLocation.rawValue)
        XCTAssertEqual(ExtensionInstaller.state(for: notInApplications),
                       .failed("TetherCam.app must be in /Applications"))

        let foreign = NSError(domain: "at.gotzendorfer.test", code: 42)
        guard case .failed = ExtensionInstaller.state(for: foreign) else {
            return XCTFail("a foreign error must stay a failure")
        }
    }
}
