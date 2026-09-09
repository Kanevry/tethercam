// SPDX-License-Identifier: MIT
import CoreMedia
import CoreVideo
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
    func testDeviceAbsentOnThisMachine() throws {
        XCTAssertFalse(CMIOSink.isDevicePresent())
        let sink = CMIOSink()
        XCTAssertThrowsError(try sink.connect()) { error in
            XCTAssertEqual(error as? CMIOSinkError, .deviceNotFound)
        }
        XCTAssertFalse(sink.isConnected)
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
