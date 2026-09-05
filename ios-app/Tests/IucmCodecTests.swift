import XCTest
@testable import UsbCam

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
        roundTrip(.hello(version: 0x0100, deviceName: "", appVersion: "", cameras: []))
    }

    func testStartRoundTrip() {
        roundTrip(.start(StartParams(cameraId: 2, width: 1920, height: 1080,
                                     fps: 30, bitrateKbps: 12000)))
    }

    func testStopRoundTrip() { roundTrip(.stop) }

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
}
