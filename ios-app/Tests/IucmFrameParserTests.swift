import XCTest
@testable import UsbCam

final class IucmFrameParserTests: XCTestCase {

    func testSingleFrame() throws {
        let p = IucmFrameParser()
        let msgs = try p.feedMessages(IucmCodec.encode(.stop))
        XCTAssertEqual(msgs, [.stop])
        XCTAssertEqual(p.bufferedByteCount, 0)
    }

    func testTwoFramesInOneChunk() throws {
        let p = IucmFrameParser()
        var d = IucmCodec.encode(.ping(timestampUs: 1))
        d.append(IucmCodec.encode(.pong(timestampUs: 2)))
        XCTAssertEqual(try p.feedMessages(d), [.ping(timestampUs: 1), .pong(timestampUs: 2)])
    }

    func testByteByByteFeed() throws {
        let p = IucmFrameParser()
        let d = IucmCodec.encode(.config(width: 1920, height: 1080, fps: 30,
                                         hvcC: Data(repeating: 0xAB, count: 90)))
        var got: [IucmMessage] = []
        for b in d { got += try p.feedMessages(Data([b])) }
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first, .config(width: 1920, height: 1080, fps: 30,
                                          hvcC: Data(repeating: 0xAB, count: 90)))
    }

    func testSplitAcrossHeaderBoundary() throws {
        let p = IucmFrameParser()
        let d = IucmCodec.encode(.start(StartParams(cameraId: 0, width: 1280, height: 720,
                                                    fps: 60, bitrateKbps: 8000)))
        XCTAssertEqual(try p.feedMessages(d.prefix(7)), [])
        XCTAssertEqual(try p.feedMessages(d.dropFirst(7)).count, 1)
    }

    func testJunkBeforeMagicIsResynced() throws {
        let p = IucmFrameParser()
        var d = Data([0x00, 0xFF, 0x49, 0x55, 0x41, 0x42, 0x13])  // includes a fake "IUA"
        d.append(IucmCodec.encode(.stop))
        XCTAssertEqual(try p.feedMessages(d), [.stop])
        XCTAssertGreaterThan(p.resyncCount, 0)
        XCTAssertEqual(p.droppedBytes, 7)
    }

    func testRecoversAfterACorruptedFrameBody() throws {
        let p = IucmFrameParser()
        // A frame whose header is valid but whose body was cut short by a lost
        // chunk. The parser consumes the announced length, mis-frames once, and
        // must be back in sync for the following complete frames.
        var d = Data(IucmCodec.encode(.ping(timestampUs: 9)).prefix(14))  // 14 of 20 bytes
        d.append(IucmCodec.encode(.stop))
        _ = try p.feedMessages(d)

        var recovered: [IucmMessage] = []
        for _ in 0..<3 {
            recovered += try p.feedMessages(IucmCodec.encode(.ping(timestampUs: 7)))
        }
        XCTAssertEqual(recovered, Array(repeating: .ping(timestampUs: 7), count: 3),
                       "parser must resync and deliver every later frame")
        XCTAssertEqual(p.bufferedByteCount, 0)
    }

    func testOversizedLengthThrows() {
        let p = IucmFrameParser()
        var d = Data(Iucm.magic)
        d.append(contentsOf: [IucmType.video.rawValue, 0, 0, 0])
        d.append(contentsOf: [0xFF, 0xFF, 0xFF, 0x7F])  // ~2 GiB
        XCTAssertThrowsError(try p.feed(d)) { e in
            guard case IucmFrameParser.ParseError.oversizedPayload = e else {
                return XCTFail("wrong error \(e)")
            }
        }
    }

    func testResetClearsBuffer() throws {
        let p = IucmFrameParser()
        _ = try p.feed(IucmCodec.encode(.stop).prefix(5))
        XCTAssertGreaterThan(p.bufferedByteCount, 0)
        p.reset()
        XCTAssertEqual(p.bufferedByteCount, 0)
    }

    func testLargeVideoFrame() throws {
        let p = IucmFrameParser()
        let nal = HvccNal.join([Data(repeating: 0x5A, count: 500_000)])
        let d = IucmCodec.encode(.video(ptsUs: 77, keyframe: true, nalUnits: nal))
        var got: [IucmMessage] = []
        var i = 0
        while i < d.count {
            let end = min(i + 9000, d.count)
            got += try p.feedMessages(d[i..<end])
            i = end
        }
        XCTAssertEqual(got, [.video(ptsUs: 77, keyframe: true, nalUnits: nal)])
    }
}
