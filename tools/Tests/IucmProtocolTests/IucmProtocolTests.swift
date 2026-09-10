import XCTest
@testable import IucmProtocol
@testable import usbcam_recv
@testable import usbcam_sim

final class CodecRoundTripTests: XCTestCase {

    private func roundTrip(_ m: IucmMessage, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try IucmCodec.encode(m)
        let back = try IucmCodec.decode(data)
        XCTAssertEqual(back, m, file: file, line: line)
    }

    func testHeaderLayout() throws {
        let data = try IucmCodec.encode(.ping(0x0102030405060708))
        let bytes = [UInt8](data)
        XCTAssertEqual(Array(bytes[0..<4]), Array("IUCM".utf8))
        XCTAssertEqual(bytes[4], 0x20)          // type PING
        XCTAssertEqual(bytes[5], 0x00)          // flags
        XCTAssertEqual(bytes[6], 0); XCTAssertEqual(bytes[7], 0)  // reserved
        XCTAssertEqual(Array(bytes[8..<12]), [8, 0, 0, 0])        // length LE
        XCTAssertEqual(Array(bytes[12...]), [0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01])
        XCTAssertEqual(data.count, 20)
    }

    func testHelloRoundTrip() throws {
        try roundTrip(.hello(HelloMessage(
            deviceName: "iPhone von Bernhard",
            appVersion: "0.1.0",
            cameras: [CameraInfo(id: 0, position: .back, name: "Rueckkamera"),
                      CameraInfo(id: 1, position: .front, name: "Frontkamera")])))
    }

    func testHelloVersionIsOneDotTwo() throws {
        let data = try IucmCodec.encode(.hello(HelloMessage(deviceName: "x", appVersion: "y", cameras: [])))
        XCTAssertEqual(Iucm.version, 0x0102)
        XCTAssertEqual([UInt8](data)[12], 0x02)   // LE low byte = minor
        XCTAssertEqual([UInt8](data)[13], 0x01)   // high byte = major
    }

    /// Golden bytes shared with `shared/tests/fixtures/clientinfo-macapp.bin`. A field
    /// order or prefix-width change here would still round-trip in Swift but stop the
    /// C and ObjC++ sides from reading the same frame.
    func testClientInfoGoldenBytesMatchTheSharedFixture() throws {
        let data = try IucmCodec.encode(.clientInfo(
            ClientInfoMessage(kind: .macApp, name: "TetherCam for Mac", version: "0.3.0")))
        var expected = Data(Iucm.magic)
        expected.append(contentsOf: [0x04, 0x00, 0x00, 0x00, 0x19, 0x00, 0x00, 0x00])
        expected.append(contentsOf: [0x02, 17])
        expected.append(contentsOf: Array("TetherCam for Mac".utf8))
        expected.append(contentsOf: [5])
        expected.append(contentsOf: Array("0.3.0".utf8))
        XCTAssertEqual(data, expected)
        try roundTrip(.clientInfo(ClientInfoMessage(kind: .tool, name: "usbcam-recv", version: "dev")))
    }

    func testClientInfoUnknownKindMapsToUnknownAndIgnoresTrailingBytes() throws {
        let m = try IucmCodec.decodePayload(type: 0x04, flags: 0,
                                            payload: [9, 1, 0x78, 1, 0x79, 0xAA])
        guard case .clientInfo(let c) = m else { return XCTFail("expected clientInfo, got \(m)") }
        XCTAssertEqual(c.kind, 9)
        XCTAssertEqual(c.clientKind, .unknown)
        XCTAssertEqual(c.name, "x")
        XCTAssertEqual(c.version, "y")
    }

    /// Bug caught: a CLIENT_INFO whose length byte outruns the payload must fail
    /// as truncated instead of reading past the buffer or handing the simulator a
    /// half-decoded identity. The C parser covers this (`test_frame_parser.c`,
    /// IUCM_ERR_TRUNCATED); the Swift decoder's trailing `rest()` forgives only
    /// SURPLUS bytes, so missing ones needed their own guard.
    func testClientInfoWithLengthByteBeyondThePayloadIsTruncated() {
        // kind 2, name "x", then version_len 5 with nothing behind it.
        XCTAssertThrowsError(try IucmCodec.decodePayload(type: 0x04, flags: 0,
                                                         payload: [2, 1, 0x78, 5])) { err in
            XCTAssertEqual(err as? IucmProtocolError, .truncatedPayload(type: 0x04))
        }
        // name_len 255, two bytes of payload behind it.
        XCTAssertThrowsError(try IucmCodec.decodePayload(type: 0x04, flags: 0,
                                                         payload: [2, 255, 0x61, 0x62])) { err in
            XCTAssertEqual(err as? IucmProtocolError, .truncatedPayload(type: 0x04))
        }
        // An empty payload does not even carry the kind byte.
        XCTAssertThrowsError(try IucmCodec.decodePayload(type: 0x04, flags: 0,
                                                         payload: [])) { err in
            XCTAssertEqual(err as? IucmProtocolError, .truncatedPayload(type: 0x04))
        }
    }

    func testStartRoundTrip() throws {
        try roundTrip(.start(StartMessage(cameraId: 0, width: 1280, height: 720, fps: 30, bitrateKbps: 6000)))
    }

    func testStopRoundTrip() throws {
        try roundTrip(.stop)
        XCTAssertEqual(try IucmCodec.encode(.stop).count, Iucm.headerSize)
    }

    func testConfigRoundTrip() throws {
        try roundTrip(.config(ConfigMessage(width: 1920, height: 1080, fps: 60,
                                            hvcc: Data([0x01, 0x02, 0xAA, 0xBB, 0xCC]))))
    }

    func testVideoRoundTripKeyframeFlag() throws {
        let nal = Data([0x00, 0x00, 0x00, 0x03, 0x26, 0x01, 0x02])
        try roundTrip(.video(VideoMessage(ptsUs: 123_456_789, isKeyframe: true, nalData: nal)))
        try roundTrip(.video(VideoMessage(ptsUs: 0, isKeyframe: false, nalData: nal)))
        let key = try IucmCodec.encode(.video(VideoMessage(ptsUs: 1, isKeyframe: true, nalData: nal)))
        XCTAssertEqual([UInt8](key)[5], 0x01)
        let delta = try IucmCodec.encode(.video(VideoMessage(ptsUs: 1, isKeyframe: false, nalData: nal)))
        XCTAssertEqual([UInt8](delta)[5], 0x00)
    }

    func testPingPongRoundTrip() throws {
        try roundTrip(.ping(1_725_000_000_000_000))
        try roundTrip(.pong(1_725_000_000_000_000))
    }

    func testErrorRoundTrip() throws {
        try roundTrip(.error(ErrorMessage(.busy, "another receiver is connected")))
        try roundTrip(.error(ErrorMessage(.versionUnsupported, "Umlaute: äöüß")))
    }

    // MARK: - Audio, PROTOCOL.md 4.2/4.9/4.10

    func testStartShortFormIsElevenBytesAndDecodesAsNoAudio() throws {
        let data = try IucmCodec.encode(.start(StartMessage(cameraId: 1, width: 1920, height: 1080,
                                                            fps: 30, bitrateKbps: 12000)))
        XCTAssertEqual(Array([UInt8](data)[8..<12]), [11, 0, 0, 0])
        guard case let .start(m) = try IucmCodec.decode(data) else { return XCTFail("not start") }
        XCTAssertEqual(m.flags, 0)
        XCTAssertFalse(m.wantsAudio)
    }

    func testStartWithAudioFlagIsTwelveBytes() throws {
        var m = StartMessage(cameraId: 1, width: 1920, height: 1080, fps: 30, bitrateKbps: 12000)
        m.wantsAudio = true
        XCTAssertEqual(m.flags, StartMessage.flagAudio)
        let data = try IucmCodec.encode(.start(m))
        XCTAssertEqual(Array([UInt8](data)[8..<12]), [12, 0, 0, 0])
        XCTAssertEqual([UInt8](data)[23], 0x01)          // flags byte at payload offset 11
        try roundTrip(.start(m))
    }

    func testStartFromAFutureMinorVersionIgnoresExtraBytes() throws {
        // 14-byte START: 11 fixed + flags + two bytes a later 1.x may add.
        let payload: [UInt8] = [1, 0x80, 0x07, 0x38, 0x04, 30, 0, 0xE0, 0x2E, 0, 0, 0x01, 0xAB, 0xCD]
        guard case let .start(m) = try IucmCodec.decodePayload(type: 0x02, flags: 0, payload: payload)
        else { return XCTFail("not start") }
        XCTAssertTrue(m.wantsAudio)
        XCTAssertEqual(m.width, 1920)
    }

    func testAudioConfigRoundTrip() throws {
        let m = AudioConfigMessage(sampleRate: 48000, channels: 1, codec: .aacLC,
                                   asc: Data([0x11, 0x88]))
        XCTAssertEqual(m.codec, IucmAudioCodec.aacLC.rawValue)
        let data = try IucmCodec.encode(.audioConfig(m))
        XCTAssertEqual([UInt8](data)[4], 0x13)
        XCTAssertEqual(Array([UInt8](data)[8..<12]), [10, 0, 0, 0])   // 8 fixed + 2 asc
        XCTAssertEqual(Array([UInt8](data)[12..<16]), [0x80, 0xBB, 0x00, 0x00])  // 48000 LE
        try roundTrip(.audioConfig(m))
        try roundTrip(.audioConfig(AudioConfigMessage(sampleRate: 44100, channels: 2,
                                                      codec: 1, asc: Data())))
    }

    func testAudioConfigRejectsTruncatedAsc() {
        XCTAssertThrowsError(try IucmCodec.decodePayload(
            type: 0x13, flags: 0,
            payload: [0x80, 0xBB, 0x00, 0x00, 0x01, 0x01, 0x04, 0x00, 0xAA]))  // asc_len 4, 1 byte
    }

    func testAudioRoundTripAndEmptyFrameIsAllowed() throws {
        let frame = Data((0..<180).map { UInt8($0 % 251) })
        let data = try IucmCodec.encode(.audio(AudioMessage(ptsUs: 1_725_000_000_000_000, frame: frame)))
        XCTAssertEqual([UInt8](data)[4], 0x14)
        XCTAssertEqual([UInt8](data)[5], 0x00)                        // header flags are 0
        XCTAssertEqual(data.count, Iucm.headerSize + 8 + frame.count)
        try roundTrip(.audio(AudioMessage(ptsUs: 1_725_000_000_000_000, frame: frame)))
        // An empty frame is legal on the wire: senders must not emit it, receivers skip it.
        try roundTrip(.audio(AudioMessage(ptsUs: 0, frame: Data())))
    }

    // MARK: - Receiver START flags: audio bit only for apps announcing 1.1 (2026-09-09 device finding)

    func testReceiverSendsAudioFlagOnlyToProtocol11Apps() {
        XCTAssertEqual(Receiver.startFlags(audio: true, helloVersion: 0x0100), 0,
                       "a 1.0 app (App Store 0.1.0) drops a 12-byte START silently: send the short form")
        XCTAssertEqual(Receiver.startFlags(audio: true, helloVersion: 0x0101), StartMessage.flagAudio)
        XCTAssertEqual(Receiver.startFlags(audio: true, helloVersion: 0x0102), StartMessage.flagAudio,
                       "later minors keep the audio bit (version rule PROTOCOL.md 4.1)")
        XCTAssertEqual(Receiver.startFlags(audio: false, helloVersion: 0x0101), 0)
    }

    // MARK: - Receiver audio decision logic, no socket needed (case a/c review fix)

    func testReceiverTreatsSecondAudioConfigAsChange() {
        let first = AudioConfigMessage(sampleRate: 48000, channels: 1, codec: .aacLC, asc: Data([0x11, 0x88]))
        XCTAssertFalse(Receiver.isAudioConfigChange(existingConfig: nil),
                        "the first AUDIO_CONFIG in a session must not count as a change")
        XCTAssertTrue(Receiver.isAudioConfigChange(existingConfig: first),
                      "a second AUDIO_CONFIG (rate/channel/codec change) must count as a change, "
                      + "not a protocol violation (PROTOCOL.md 4.9)")
    }

    func testReceiverDropsAudioBeforeConfigWithoutThrowing() {
        XCTAssertTrue(Receiver.shouldDropAudio(hasConfig: false, frameIsEmpty: false),
                      "AUDIO before AUDIO_CONFIG must be dropped, not treated as a protocol "
                      + "violation (PROTOCOL.md 4.10)")
        XCTAssertFalse(Receiver.shouldDropAudio(hasConfig: true, frameIsEmpty: false),
                       "AUDIO with a config present and a non-empty payload must be processed")
    }

    func testMicDeniedErrorCode() throws {
        XCTAssertEqual(IucmErrorCode.micDenied.rawValue, 6)
        try roundTrip(.error(ErrorMessage(.micDenied, "Mikrofonzugriff verweigert")))
    }

    func testAudioStatsFlagBits() {
        XCTAssertEqual(StatsMessage.flagAudioActive, 0x10)
        XCTAssertEqual(StatsMessage.flagAudioMuted, 0x20)
    }

    func testAllErrorCodes() {
        XCTAssertEqual(IucmErrorCode.busy.rawValue, 1)
        XCTAssertEqual(IucmErrorCode.cameraDenied.rawValue, 2)
        XCTAssertEqual(IucmErrorCode.formatUnsupported.rawValue, 3)
        XCTAssertEqual(IucmErrorCode.encoderFailed.rawValue, 4)
        XCTAssertEqual(IucmErrorCode.versionUnsupported.rawValue, 5)
        XCTAssertEqual(IucmErrorCode.micDenied.rawValue, 6)
    }
}

final class FrameParserTests: XCTestCase {

    func testTwoMessagesInOneRead() throws {
        var p = IucmFrameParser()
        var data = try IucmCodec.encode(.ping(1))
        data.append(try IucmCodec.encode(.stop))
        let out = try p.append(data)
        XCTAssertEqual(out, [.ping(1), .stop])
        XCTAssertEqual(p.bufferedByteCount, 0)
    }

    func testPartialFrameOverManyReads() throws {
        let msg = IucmMessage.hello(HelloMessage(deviceName: "Simulator", appVersion: "0.1.0",
                                                 cameras: [CameraInfo(id: 0, position: .back, name: "Simulator")]))
        let data = try IucmCodec.encode(msg)
        var p = IucmFrameParser()
        var collected: [IucmMessage] = []
        for byte in data {                     // one byte at a time — worst case
            collected += try p.append(Data([byte]))
        }
        XCTAssertEqual(collected, [msg])
        XCTAssertEqual(p.bufferedByteCount, 0)
    }

    func testSplitHeaderAcrossReads() throws {
        let data = try IucmCodec.encode(.start(StartMessage(cameraId: 0, width: 640, height: 480, fps: 25, bitrateKbps: 900)))
        var p = IucmFrameParser()
        XCTAssertEqual(try p.append(data.prefix(2)), [])
        XCTAssertEqual(try p.append(data.dropFirst(2).prefix(9)), [])
        let out = try p.append(data.dropFirst(11))
        XCTAssertEqual(out.count, 1)
    }

    func testGarbageBeforeMagicIsDropped() throws {
        var data = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x49, 0x55, 0x43])  // includes a fake partial magic
        data.append(try IucmCodec.encode(.ping(7)))
        var p = IucmFrameParser()
        XCTAssertEqual(try p.append(data), [.ping(7)])
        XCTAssertEqual(p.resyncDroppedBytes, 7)
        XCTAssertEqual(p.bufferedByteCount, 0)
    }

    func testGarbageOnlyKeepsAtMostThreeBytes() throws {
        var p = IucmFrameParser()
        XCTAssertEqual(try p.append(Data(repeating: 0x00, count: 100)), [])
        XCTAssertLessThanOrEqual(p.bufferedByteCount, 3)
    }

    func testOverlongLengthIsRejected() throws {
        var header = Data(Iucm.magic)
        header.append(contentsOf: [0x11, 0x00, 0x00, 0x00])       // VIDEO, no flags, reserved
        header.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF])       // length 4 GiB
        var p = IucmFrameParser()
        XCTAssertThrowsError(try p.append(header)) { err in
            guard case IucmProtocolError.payloadTooLarge(let n) = err else {
                return XCTFail("expected payloadTooLarge, got \(err)")
            }
            XCTAssertEqual(n, 0xFFFF_FFFF)
        }
    }

    func testTruncatedPayloadForFixedLayoutThrows() throws {
        var frame = Data(Iucm.magic)
        frame.append(contentsOf: [0x02, 0x00, 0x00, 0x00])        // START
        frame.append(contentsOf: [0x03, 0x00, 0x00, 0x00])        // length 3 — START needs 11
        frame.append(contentsOf: [0x00, 0x00, 0x00])
        var p = IucmFrameParser()
        XCTAssertThrowsError(try p.append(frame)) { err in
            guard case IucmProtocolError.truncatedPayload = err else {
                return XCTFail("expected truncatedPayload, got \(err)")
            }
        }
    }

    func testTrailingBytesRejected() throws {
        var frame = Data(Iucm.magic)
        frame.append(contentsOf: [0x20, 0x00, 0x00, 0x00])        // PING
        frame.append(contentsOf: [0x09, 0x00, 0x00, 0x00])        // length 9 — one too many
        frame.append(contentsOf: [UInt8](repeating: 0, count: 9))
        var p = IucmFrameParser()
        XCTAssertThrowsError(try p.append(frame)) { err in
            guard case IucmProtocolError.trailingBytes = err else {
                return XCTFail("expected trailingBytes, got \(err)")
            }
        }
    }

    func testUnknownTypeThrows() throws {
        var frame = Data(Iucm.magic)
        frame.append(contentsOf: [0x99, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        var p = IucmFrameParser()
        XCTAssertThrowsError(try p.append(frame)) { err in
            guard case IucmProtocolError.unknownType(0x99) = err else {
                return XCTFail("expected unknownType, got \(err)")
            }
        }
    }

    func testStreamOfManyVideoFrames() throws {
        var stream = Data()
        var expected: [IucmMessage] = []
        for i in 0..<50 {
            let m = IucmMessage.video(VideoMessage(ptsUs: UInt64(i) * 33_333,
                                                   isKeyframe: i % 30 == 0,
                                                   nalData: Data(repeating: UInt8(i % 251), count: 100 + i)))
            expected.append(m)
            stream.append(try IucmCodec.encode(m))
        }
        var p = IucmFrameParser()
        var got: [IucmMessage] = []
        var offset = 0
        while offset < stream.count {                    // irregular chunking
            let n = min(37, stream.count - offset)
            got += try p.append(stream.subdata(in: offset..<(offset + n)))
            offset += n
        }
        XCTAssertEqual(got, expected)
    }

    func testStatsRoundTrip() throws {
        let m = StatsMessage(continuousAngleX10: 123, sector: 0, residualX10: -45,
                             gravityMX1000: 870, levelerMsX10: 37, droppedFrames: 2,
                             sourceWidth: 3840, sourceHeight: 2160,
                             outputWidth: 1920, outputHeight: 1080,
                             flags: StatsMessage.flagAutoRotation | StatsMessage.flagHorizonLeveling,
                             cameraId: 1)
        let frame = try IucmCodec.encode(.stats(m))
        XCTAssertEqual(frame[4], 0x12)
        XCTAssertEqual(frame.count, Iucm.headerSize + 22)
        let back = try IucmCodec.decodePayload(type: 0x12, flags: 0,
                                               payload: Array(frame[Iucm.headerSize...]))
        XCTAssertEqual(back, .stats(m))
        guard case let .stats(s) = back else { return XCTFail("not stats") }
        XCTAssertEqual(s.continuousDeg, 12.3, accuracy: 0.001)
        XCTAssertEqual(s.residualDeg, -4.5, accuracy: 0.001)
        XCTAssertEqual(s.gravityM, 0.87, accuracy: 0.001)
        XCTAssertEqual(s.levelerMs, 3.7, accuracy: 0.001)
    }

    func testStatsRejectsShortPayload() {
        XCTAssertThrowsError(try IucmCodec.decodePayload(type: 0x12, flags: 0,
                                                         payload: [UInt8](repeating: 0, count: 21)))
    }
}

/// Audio side of protocol 1.1 (PROTOCOL.md 4.9/4.10): the sim's AAC tone encoder,
/// the receiver's ADTS framing, and that one survives the other.
final class AudioToolingTests: XCTestCase {

    func testToneEncoderProducesCookieAndFrames() throws {
        let encoder = try AacToneEncoder()
        let cookie = try encoder.magicCookie()
        XCTAssertFalse(cookie.isEmpty, "AudioSpecificConfig must not be empty")

        let frame = try encoder.nextFrame()
        XCTAssertFalse(frame.isEmpty, "AAC access unit must not be empty")
        // A 1024-sample AAC-LC frame at 64 kbit/s is a few hundred bytes, never 8 kB.
        XCTAssertLessThan(frame.count, 8192)
        XCTAssertFalse(try encoder.nextFrame().isEmpty, "encoder must keep producing frames")
    }

    func testEncodedFrameDecodesTo1024Samples() throws {
        let encoder = try AacToneEncoder()
        let cookie = try encoder.magicCookie()
        let decoder = try AacDecoder(sampleRate: encoder.sampleRate,
                                     channels: encoder.channels, asc: cookie)
        // The first access units are encoder priming; by the third the decoder
        // returns a full 1024-sample block.
        var samples = 0
        for _ in 0..<4 { samples = try decoder.decode(frame: try encoder.nextFrame()) }
        XCTAssertEqual(samples, AacDecoder.samplesPerFrame)
    }

    func testAdtsHeaderLayout() throws {
        let payload = 500
        let h = try XCTUnwrap(Adts.header(payloadLength: payload, sampleRate: 48_000, channels: 1))
        XCTAssertEqual(h.count, 7)
        let b = [UInt8](h)
        XCTAssertEqual(b[0], 0xFF)
        XCTAssertEqual(b[1] & 0xF6, 0xF0)              // syncword, MPEG-4, layer 00
        XCTAssertEqual(b[1] & 0x01, 0x01)              // protection absent (no CRC)
        XCTAssertEqual((b[2] >> 6) & 0x03, 1)          // profile 1 = AAC-LC
        XCTAssertEqual((b[2] >> 2) & 0x0F, 3)          // sampling index 3 = 48000 Hz
        let channels = (Int(b[2] & 0x01) << 2) | (Int(b[3] >> 6) & 0x03)
        XCTAssertEqual(channels, 1)
        let frameLength = (Int(b[3] & 0x03) << 11) | (Int(b[4]) << 3) | (Int(b[5] >> 5) & 0x07)
        XCTAssertEqual(frameLength, payload + Adts.headerSize)
    }

    func testAdtsHeaderRejectsUnsupportedFields() {
        XCTAssertNil(Adts.header(payloadLength: 100, sampleRate: 47_000, channels: 1))
        XCTAssertNil(Adts.header(payloadLength: 0, sampleRate: 48_000, channels: 1))
        XCTAssertNil(Adts.header(payloadLength: 100, sampleRate: 48_000, channels: 0))
        XCTAssertNil(Adts.header(payloadLength: 1 << 13, sampleRate: 48_000, channels: 1))
    }
}
