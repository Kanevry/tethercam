// SPDX-License-Identifier: MIT
import CoreVideo
import Darwin
import Foundation
import IucmProtocol
import XCTest
@testable import TetherCamCore

/// Runs tools/.build/release/usbcam-sim for one test and kills exactly that PID.
final class SimHarness {
    static let binary: String = {
        let here = URL(fileURLWithPath: #filePath)
        return here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/.build/release/usbcam-sim").path
    }()

    let port: UInt16
    private let process = Process()

    init(port: UInt16) throws {
        self.port = port
        guard FileManager.default.isExecutableFile(atPath: Self.binary) else {
            throw XCTSkip("usbcam-sim missing at \(Self.binary); run: swift build --package-path tools -c release --product usbcam-sim")
        }
        process.executableURL = URL(fileURLWithPath: Self.binary)
        process.arguments = ["--bind", "127.0.0.1", "--port", String(port), "--no-audio"]
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        // Wait for the listener. The probe counts as the sim's single client until
        // its Network.framework connection reports "peer closed", so give it a
        // moment; otherwise the real session is answered with ERROR 1 BUSY.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let fd = try? Transport.connectTCP(host: "127.0.0.1", port: port) {
                close(fd)
                usleep(300_000)
                return
            }
            usleep(50_000)
        }
        process.terminate()
        throw XCTSkip("usbcam-sim did not open port \(port)")
    }

    func stop() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
    }
}

final class DecoderTests: XCTestCase {

    /// Bug caught: any break in connect -> HELLO -> START -> CONFIG -> decode ->
    /// scale -> onFrame. Asserts the contract format on every delivered frame.
    func testLiveSimEndToEndDeliversScaledFrames() throws {
        let sim = try SimHarness(port: 7981)
        defer { sim.stop() }

        let receiver = Receiver(config: ReceiverConfig(endpoint: .tcp(host: "127.0.0.1", port: 7981)))
        let states = Locked<[LinkState]>([])
        let configs = Locked<[(Int, Int, Int)]>([])
        let frames = Locked<Int>(0)
        let badFrames = Locked<Int>(0)
        receiver.onState = { st in states.with { $0.append(st) } }
        receiver.onConfig = { w, h, f in configs.with { $0.append((w, h, f)) } }
        receiver.onFrame = { pb, _ in
            let ok = CVPixelBufferGetWidth(pb) == 1920 && CVPixelBufferGetHeight(pb) == 1080
                && CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                && CVPixelBufferGetIOSurface(pb) != nil
            if ok { frames.with { $0 += 1 } } else { badFrames.with { $0 += 1 } }
        }
        receiver.start()
        defer { receiver.stop() }

        let deadline = Date().addingTimeInterval(5)
        while frames.value < 10 && Date() < deadline { usleep(20_000) }

        XCTAssertTrue(states.value.contains(.streaming), "states: \(states.value)")
        XCTAssertEqual(configs.value.first.map { "\($0.0)x\($0.1)@\($0.2)" }, "1920x1080@30")
        XCTAssertGreaterThanOrEqual(frames.value, 10)
        XCTAssertEqual(badFrames.value, 0)
    }

    /// Captures hvcC + the first VIDEO messages straight from the sim (no fixture
    /// file to keep in sync with the encoder).
    private func captureStream(port: UInt16, videoCount: Int) throws -> (ConfigMessage, [VideoMessage]) {
        let fd = try Transport.connectTCP(host: "127.0.0.1", port: port)
        defer { close(fd) }
        var parser = IucmFrameParser()
        var config: ConfigMessage?
        var videos: [VideoMessage] = []
        var buf = [UInt8](repeating: 0, count: 1 << 16)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && videos.count < videoCount {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            for msg in try parser.append(Data(buf[0..<n])) {
                switch msg {
                case .hello:
                    try Transport.sendAll(fd, try IucmCodec.encode(.start(StartMessage(
                        cameraId: 0, width: 1280, height: 720, fps: 30, bitrateKbps: 4000, flags: 0))))
                case .config(let c): config = c
                case .video(let v): videos.append(v)
                default: break
                }
            }
        }
        try? Transport.sendAll(fd, try IucmCodec.encode(.stop))
        guard let config else { throw XCTSkip("sim sent no CONFIG") }
        return (config, videos)
    }

    /// Bug caught: a decoder that submits P-frames before its first keyframe
    /// produces garbage or VideoToolbox errors; one that never decodes at all.
    func testKeyframeGateAndDecodedFormat() throws {
        let sim = try SimHarness(port: 7982)
        defer { sim.stop() }
        let (config, videos) = try captureStream(port: 7982, videoCount: 20)
        XCTAssertGreaterThanOrEqual(videos.count, 12)
        XCTAssertTrue(videos.first?.isKeyframe ?? false, "sim must start with a keyframe")
        guard let nonKey = videos.first(where: { !$0.isKeyframe }) else {
            throw XCTSkip("stream contains no non-keyframe in the first \(videos.count) frames")
        }

        let decoder = try HevcDecoder(hvcC: config.hvcc, width: Int(config.width), height: Int(config.height))
        let out = Locked<[(Int, Int, OSType)]>([])
        decoder.onFrame = { pb, _ in
            out.with { $0.append((CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), CVPixelBufferGetPixelFormatType(pb))) }
        }
        // Leading non-keyframe is dropped, not decoded.
        XCTAssertEqual(decoder.decode(nalData: nonKey.nalData, ptsUs: Int64(nonKey.ptsUs), keyframe: false),
                       .droppedAwaitingKeyframe)
        XCTAssertTrue(decoder.isWaitingForKeyframe)

        for v in videos {
            XCTAssertEqual(decoder.decode(nalData: v.nalData, ptsUs: Int64(v.ptsUs), keyframe: v.isKeyframe), .accepted)
        }
        decoder.close()
        XCTAssertGreaterThanOrEqual(out.value.count, 10)
        for (w, h, fmt) in out.value {
            XCTAssertEqual(w, Int(config.width))
            XCTAssertEqual(h, Int(config.height))
            XCTAssertEqual(fmt, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        }
    }

    // MARK: - FrameScaler

    private func makeNV12(width: Int, height: Int, luma: UInt8) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                           kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                           attrs as CFDictionary, &pb), kCVReturnSuccess)
        let buf = pb!
        CVPixelBufferLockBaseAddress(buf, [])
        memset(CVPixelBufferGetBaseAddressOfPlane(buf, 0), Int32(luma),
               CVPixelBufferGetBytesPerRowOfPlane(buf, 0) * height)
        memset(CVPixelBufferGetBaseAddressOfPlane(buf, 1), 128,
               CVPixelBufferGetBytesPerRowOfPlane(buf, 1) * (height / 2))
        CVPixelBufferUnlockBaseAddress(buf, [])
        return buf
    }

    private func luma(_ buf: CVPixelBuffer, x: Int, y: Int) -> UInt8 {
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        let base = CVPixelBufferGetBaseAddressOfPlane(buf, 0)!.assumingMemoryBound(to: UInt8.self)
        return base[y * CVPixelBufferGetBytesPerRowOfPlane(buf, 0) + x]
    }

    /// Bug caught: kVTScalingMode_Letterbox silently stretching (or cropping) a
    /// portrait frame instead of pillarboxing it with black.
    func testScalerLetterboxesPortraitWithBlackColumns() throws {
        let scaler = try FrameScaler()
        let white = makeNV12(width: 1080, height: 1920, luma: 235)
        let out = try XCTUnwrap(scaler.scale(white))
        XCTAssertEqual(CVPixelBufferGetWidth(out), 1920)
        XCTAssertEqual(CVPixelBufferGetHeight(out), 1080)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(out), kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        XCTAssertNotNil(CVPixelBufferGetIOSurface(out))
        XCTAssertLessThanOrEqual(luma(out, x: 10, y: 540), 20, "left bar must be black")
        XCTAssertLessThanOrEqual(luma(out, x: 1909, y: 540), 20, "right bar must be black")
        XCTAssertGreaterThanOrEqual(luma(out, x: 960, y: 540), 225, "centre column must carry the image")
        XCTAssertFalse(out === white)
    }

    /// Bug caught: a needless copy of an already conforming frame.
    func testScalerPassesThroughMatchingBuffer() throws {
        let scaler = try FrameScaler()
        let input = makeNV12(width: 1920, height: 1080, luma: 100)
        let out = try XCTUnwrap(scaler.scale(input))
        XCTAssertTrue(out === input)
    }
}
