import XCTest
@testable import IucmProtocol

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

    func testHelloVersionIsOneDotZero() throws {
        let data = try IucmCodec.encode(.hello(HelloMessage(deviceName: "x", appVersion: "y", cameras: [])))
        XCTAssertEqual(Iucm.version, 0x0100)
        XCTAssertEqual([UInt8](data)[12], 0x00)   // LE low byte = minor
        XCTAssertEqual([UInt8](data)[13], 0x01)   // high byte = major
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

    func testAllErrorCodes() {
        XCTAssertEqual(IucmErrorCode.busy.rawValue, 1)
        XCTAssertEqual(IucmErrorCode.cameraDenied.rawValue, 2)
        XCTAssertEqual(IucmErrorCode.formatUnsupported.rawValue, 3)
        XCTAssertEqual(IucmErrorCode.encoderFailed.rawValue, 4)
        XCTAssertEqual(IucmErrorCode.versionUnsupported.rawValue, 5)
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
}
