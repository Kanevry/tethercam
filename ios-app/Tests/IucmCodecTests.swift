import XCTest
@testable import TetherCam

final class IucmCodecTests: XCTestCase {

    private func roundTrip(_ m: IucmMessage, file: StaticString = #filePath, line: UInt = #line) {
        let frame = IucmCodec.encode(m)
        XCTAssertEqual(Array(frame.prefix(4)), Iucm.magic, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.count, Iucm.headerSize, file: file, line: line)
        do {
            XCTAssertEqual(try IucmCodec.decodeFrame(frame), m, file: file, line: line)
        } catch {
            XCTFail("decode failed: \(error)", file: file, line: line)
        }
    }

    func testHelloRoundTrip() {
        roundTrip(.hello(version: Iucm.version, deviceName: "Bernhards iPhone",
                         appVersion: "1.0", cameras: [
                            CameraDescriptor(id: 0, position: .back, name: "Rueck-Weitwinkel"),
                            CameraDescriptor(id: 1, position: .back, name: "Rueck-Ultraweit"),
                            CameraDescriptor(id: 3, position: .front, name: "Front"),
                         ]))
    }

    func testHelloWithNoCameras() {
        roundTrip(.hello(version: 0x0101, deviceName: "", appVersion: "", cameras: []))
    }

    func testStartRoundTrip() {
        roundTrip(.start(StartParams(cameraId: 2, width: 1920, height: 1080,
                                     fps: 30, bitrateKbps: 12000)))
    }

    func testStopRoundTrip() { roundTrip(.stop) }

    // MARK: - Audio, PROTOCOL.md 4.2/4.9/4.10

    func testVersionIsOneDotOne() {
        XCTAssertEqual(Iucm.version, 0x0101)
    }

    func testStartShortFormIsElevenBytesAndDecodesAsNoAudio() throws {
        let f = IucmCodec.encode(.start(StartParams(cameraId: 1, width: 1920, height: 1080,
                                                    fps: 30, bitrateKbps: 12000)))
        XCTAssertEqual(Array(f[8..<12]), [11, 0, 0, 0])
        guard case let .start(p) = try IucmCodec.decodeFrame(f) else {
            return XCTFail("not a start message")
        }
        XCTAssertEqual(p.flags, 0)
        XCTAssertFalse(p.wantsAudio)
    }

    func testStartWithAudioFlagIsTwelveBytes() throws {
        var p = StartParams(cameraId: 1, width: 1920, height: 1080, fps: 30, bitrateKbps: 12000)
        p.wantsAudio = true
        XCTAssertEqual(p.flags, StartParams.flagAudio)
        let f = IucmCodec.encode(.start(p))
        XCTAssertEqual(Array(f[8..<12]), [12, 0, 0, 0])
        XCTAssertEqual(f[23], 0x01)                 // flags byte at payload offset 11
        roundTrip(.start(p))
    }

    func testStartFromAFutureMinorVersionIgnoresExtraBytes() throws {
        // 14-byte START: 11 fixed + flags + two bytes a later 1.x may add.
        let payload = Data([1, 0x80, 0x07, 0x38, 0x04, 30, 0, 0xE0, 0x2E, 0, 0, 0x01, 0xAB, 0xCD])
        guard case let .start(p) = try IucmCodec.decodePayload(type: 0x02, flags: 0, payload: payload)
        else { return XCTFail("not a start message") }
        XCTAssertTrue(p.wantsAudio)
        XCTAssertEqual(p.width, 1920)
    }

    func testAudioConfigRoundTripAndWireLayout() throws {
        let f = IucmCodec.encode(.audioConfig(sampleRate: 48000, channels: 1,
                                              codec: IucmAudioCodec.aacLC.rawValue,
                                              asc: Data([0x11, 0x88])))
        XCTAssertEqual(f[4], 0x13)
        XCTAssertEqual(Array(f[8..<12]), [10, 0, 0, 0])              // 8 fixed + 2 asc
        XCTAssertEqual(Array(f[12..<16]), [0x80, 0xBB, 0x00, 0x00])  // 48000 LE
        XCTAssertEqual(f[16], 1)                                     // channels
        XCTAssertEqual(f[17], 1)                                     // codec = AAC-LC
        XCTAssertEqual(Array(f[18..<20]), [0x02, 0x00])              // asc_len LE
        roundTrip(.audioConfig(sampleRate: 48000, channels: 1, codec: 1, asc: Data([0x11, 0x88])))
        roundTrip(.audioConfig(sampleRate: 44100, channels: 2, codec: 1, asc: Data()))
    }

    func testAudioConfigRejectsTruncatedAsc() {
        // asc_len says 4, only one byte follows.
        let payload = Data([0x80, 0xBB, 0x00, 0x00, 0x01, 0x01, 0x04, 0x00, 0xAA])
        XCTAssertThrowsError(try IucmCodec.decodePayload(type: 0x13, flags: 0, payload: payload)) { e in
            XCTAssertEqual(e as? IucmDecodeError, .truncatedPayload)
        }
    }

    func testAudioRoundTripAndEmptyFrameIsAllowed() throws {
        let frame = Data((0..<180).map { UInt8($0 % 251) })
        let f = IucmCodec.encode(.audio(ptsUs: 1_725_000_000_000_000, frame: frame))
        XCTAssertEqual(f[4], 0x14)
        XCTAssertEqual(f[5], 0x00)                                   // header flags are 0
        XCTAssertEqual(f.count, Iucm.headerSize + 8 + frame.count)
        roundTrip(.audio(ptsUs: 1_725_000_000_000_000, frame: frame))
        // An empty frame is legal on the wire: senders must not emit it, receivers skip it.
        roundTrip(.audio(ptsUs: 0, frame: Data()))
    }

    func testMicDeniedErrorCodeAndAudioStatsFlags() {
        XCTAssertEqual(IucmErrorCode.micDenied.rawValue, 6)
        XCTAssertEqual(DeviceStats.flagAudioActive, 0x10)
        XCTAssertEqual(DeviceStats.flagAudioMuted, 0x20)
    }

    func testConfigRoundTrip() {
        roundTrip(.config(width: 1920, height: 1080, fps: 30,
                          hvcC: Data((0..<200).map { UInt8($0 % 251) })))
    }

    func testVideoRoundTripKeyframeFlag() {
        let nals = HvccNal.join([Data([0x26, 0x01, 0xAF]), Data(repeating: 7, count: 300)])
        roundTrip(.video(ptsUs: 1_234_567_890, keyframe: true, nalUnits: nals))
        roundTrip(.video(ptsUs: 0, keyframe: false, nalUnits: nals))
    }

    func testVideoKeyframeFlagIsInHeaderBit0() throws {
        let f = IucmCodec.encode(.video(ptsUs: 5, keyframe: true, nalUnits: Data()))
        XCTAssertEqual(f[5] & 0x01, 0x01)
        let g = IucmCodec.encode(.video(ptsUs: 5, keyframe: false, nalUnits: Data()))
        XCTAssertEqual(g[5] & 0x01, 0x00)
    }

    func testPingPongRoundTrip() {
        roundTrip(.ping(timestampUs: UInt64.max))
        roundTrip(.pong(timestampUs: 42))
    }

    func testErrorRoundTrip() {
        for c in IucmErrorCode.allCases {
            roundTrip(.error(code: c.rawValue, text: "Fehler \(c) mit Umlauten: äöüß"))
        }
    }

    func testHeaderIsLittleEndian() {
        let f = IucmCodec.encode(.start(StartParams(cameraId: 1, width: 0x0780,
                                                    height: 0x0438, fps: 30, bitrateKbps: 1)))
        XCTAssertEqual(f[4], IucmType.start.rawValue)
        XCTAssertEqual(f[6], 0); XCTAssertEqual(f[7], 0)   // reserved
        XCTAssertEqual(f[8], 11)                            // payload length LE low byte
        XCTAssertEqual(f[9], 0); XCTAssertEqual(f[10], 0); XCTAssertEqual(f[11], 0)
        // width 0x0780 little-endian after the u8 camera id
        XCTAssertEqual(f[13], 0x80); XCTAssertEqual(f[14], 0x07)
    }

    func testBadMagicRejected() {
        var f = IucmCodec.encode(.stop)
        f[0] = 0x58
        XCTAssertThrowsError(try IucmCodec.decodeFrame(f)) { e in
            XCTAssertEqual(e as? IucmDecodeError, .badMagic)
        }
    }

    func testUnknownTypeRejected() {
        var f = IucmCodec.encode(.stop)
        f[4] = 0x77
        XCTAssertThrowsError(try IucmCodec.decodeFrame(f)) { e in
            XCTAssertEqual(e as? IucmDecodeError, .unknownType(0x77))
        }
    }

    func testTruncatedPayloadRejected() {
        let f = IucmCodec.encode(.ping(timestampUs: 1))
        XCTAssertThrowsError(try IucmCodec.decodeFrame(f.dropLast(3))) { e in
            XCTAssertEqual(e as? IucmDecodeError, .truncatedPayload)
        }
    }

    func testNalSplitJoinRoundTrip() throws {
        let nals = [Data([1, 2, 3]), Data(), Data(repeating: 9, count: 70000)]
        let joined = HvccNal.join(nals)
        // big-endian length prefix
        XCTAssertEqual(Array(joined.prefix(4)), [0, 0, 0, 3])
        XCTAssertEqual(HvccNal.split(joined), nals)
    }

    func testNalSplitRejectsTruncated() {
        XCTAssertNil(HvccNal.split(Data([0, 0, 0, 9, 1, 2])))
    }

    // MARK: - STATS (0x12), PROTOCOL.md 4.8

    func testStatsRoundTripAndWireLayout() throws {
        let st = DeviceStats(continuousDeg: 12.3, sector: 0, residualDeg: -4.5,
                             gravityM: 0.87, levelerMs: 3.7, droppedFrames: 2,
                             sourceWidth: 3840, sourceHeight: 2160,
                             outputWidth: 1920, outputHeight: 1080,
                             flags: DeviceStats.flagAutoRotation | DeviceStats.flagHorizonLeveling
                                 | DeviceStats.flagOversampling,
                             cameraId: 0)
        let frame = IucmCodec.encode(.stats(st))
        XCTAssertEqual(frame[4], 0x12)
        // 12-byte header + the fixed 22-byte payload
        XCTAssertEqual(frame.count, Iucm.headerSize + 22)
        XCTAssertEqual(Array(frame[8..<12]), [22, 0, 0, 0])
        // first field little-endian: 123 = 0x007B
        XCTAssertEqual(Array(frame[12..<14]), [0x7B, 0x00])
        // negative residual as two's complement: -45 = 0xFFD3
        XCTAssertEqual(Array(frame[16..<18]), [0xD3, 0xFF])

        guard case let .stats(back) = try IucmCodec.decodeFrame(frame) else {
            return XCTFail("not a stats message")
        }
        XCTAssertEqual(back, st)
        XCTAssertEqual(back.continuousDeg, 12.3, accuracy: 0.001)
        XCTAssertEqual(back.residualDeg, -4.5, accuracy: 0.001)
        XCTAssertEqual(back.gravityM, 0.87, accuracy: 0.001)
        XCTAssertEqual(back.levelerMs, 3.7, accuracy: 0.001)
    }

    func testStatsSaturatesInsteadOfTrapping() {
        // Telemetry must never crash the streaming app on an absurd input.
        let st = DeviceStats(continuousDeg: 9_999_999, sector: 0, residualDeg: -9_999_999,
                             gravityM: 5, levelerMs: 1e9, droppedFrames: Int.max,
                             sourceWidth: 100_000, sourceHeight: -5,
                             outputWidth: 0, outputHeight: 0, flags: 0xFF, cameraId: 255)
        XCTAssertEqual(st.continuousAngleX10, Int16.max)
        XCTAssertEqual(st.residualX10, Int16.min)
        XCTAssertEqual(st.droppedFrames, UInt16.max)
        XCTAssertEqual(st.sourceHeight, 0)
    }

    func testStatsRejectsTrailingBytes() {
        var frame = IucmCodec.encode(.stats(DeviceStats(continuousAngleX10: 0, sector: 0,
                                                        residualX10: 0, gravityMX1000: 0,
                                                        levelerMsX10: 0, droppedFrames: 0,
                                                        sourceWidth: 0, sourceHeight: 0,
                                                        outputWidth: 0, outputHeight: 0,
                                                        flags: 0, cameraId: 0)))
        frame[8] = 23
        frame.append(0)
        XCTAssertThrowsError(try IucmCodec.decodeFrame(frame)) { e in
            XCTAssertEqual(e as? IucmDecodeError, .trailingBytes)
        }
    }
}
