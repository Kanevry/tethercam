// SPDX-License-Identifier: MIT
import CoreVideo
import Foundation
import XCTest
@testable import TetherCamCore

final class PipelineTests: XCTestCase {

    /// Bug caught: the portrait path drops frames inside FrameScaler (the pool is
    /// capped at sinkQueueDepth + 2, `scale` returns nil), the receiver then never
    /// calls onFrame, and the menu still showed `dropped 0` while every frame was
    /// lost — `droppedAtAllocationThreshold` had no call site at all. The scaler's
    /// count must exist AND end up in PipelineStatus.dropped.
    func testScalerPoolDropsAreCountedAsDropped() throws {
        let scaler = try FrameScaler()
        let portrait = makeNV12(width: 1080, height: 1920)
        var held: [CVPixelBuffer] = []
        // Exhaust the pool: keep every scaled buffer alive until scale() gives up.
        for _ in 0..<64 {
            guard let out = scaler.scale(portrait) else { break }
            held.append(out)
        }
        XCTAssertGreaterThan(scaler.droppedAtAllocationThreshold, 0,
                             "scaler never hit its allocation threshold (held \(held.count) buffers)")

        let dropped = CameraPipeline.totalDropped(sinkDrops: 3,
                                                  scalerDrops: scaler.droppedAtAllocationThreshold)
        XCTAssertEqual(dropped, 3 + scaler.droppedAtAllocationThreshold)
        held.removeAll()
    }

    /// Bug caught: `dropped` climbing into the thousands while nothing is wrong —
    /// with no app reading the camera the sink queue stays full, `pushed` freezes
    /// and every arriving frame is dropped by design. That idle state must be
    /// derived (pushed stalled > 1 s while fps > 0) and must clear again the
    /// moment a consumer drains the queue.
    func testNoConsumerIsDerivedFromAStalledPushCounter() {
        var detector = SinkIdleDetector()
        XCTAssertFalse(detector.update(pushed: 10, fps: 30, now: 100.0), "first tick has no history")
        XCTAssertFalse(detector.update(pushed: 10, fps: 30, now: 100.5), "half a second is not a stall")
        XCTAssertTrue(detector.update(pushed: 10, fps: 30, now: 101.6), "pushed frozen for 1.6 s at fps 30")

        // A consumer (Zoom) opens the camera: the queue drains, pushed advances.
        XCTAssertFalse(detector.update(pushed: 42, fps: 30, now: 102.0))
        XCTAssertFalse(detector.noConsumer)

        // No frames arriving at all is "no iPhone", not "no consumer".
        XCTAssertFalse(detector.update(pushed: 42, fps: 0, now: 110.0))

        detector.reset()
        XCTAssertFalse(detector.noConsumer)
    }

    private func makeNV12(width: Int, height: Int) -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                           kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                           attrs as CFDictionary, &pb), kCVReturnSuccess)
        return pb!
    }

    /// Bug caught: a pipeline that refuses to receive while the Camera Extension
    /// is absent (connect() throwing deviceNotFound must not stop the receiver),
    /// or one that "pushes" frames into a sink that is not connected.
    func testLiveSimStreamsWithoutSink() throws {
        let sim = try SimHarness(port: 7983)
        defer { sim.stop() }

        let pipeline = CameraPipeline(endpoint: .tcp(host: "127.0.0.1", port: 7983))
        let statuses = Locked<[PipelineStatus]>([])
        pipeline.onStatus = { st in statuses.with { $0.append(st) } }
        pipeline.start()
        defer { pipeline.stop() }

        let devicePresent = CMIOSink.isDevicePresent()
        let deadline = Date().addingTimeInterval(6)
        func settled(_ s: PipelineStatus) -> Bool {
            guard s.received >= 10 else { return false }
            // With the extension enabled the sink connects on the streaming
            // transition, a few frames after the first decoded one.
            if devicePresent, s.camera == .ready, s.pushed + s.dropped == 0 { return false }
            return true
        }
        while !settled(pipeline.currentStatus) && Date() < deadline { usleep(20_000) }

        let final = pipeline.currentStatus
        XCTAssertTrue(statuses.value.map(\.link).contains(.streaming), "statuses: \(statuses.value.map(\.line))")
        XCTAssertGreaterThanOrEqual(final.received, 10, "frames received: \(final.received)")
        XCTAssertEqual(final.resolution, "1920x1080@30")

        if CMIOSink.isDevicePresent() {
            // Extension enabled on this machine: frames must actually reach the sink,
            // unless an installed TetherCam.app already holds the single sink client.
            if case .error(let why) = final.camera, why.contains("CMIOStreamCopyBufferQueue") {
                throw XCTSkip("sink is held by another host process (TetherCam.app running?): \(why)")
            }
            XCTAssertEqual(final.camera, .ready)
            XCTAssertGreaterThan(final.pushed + final.dropped, 0)
        } else {
            XCTAssertNotEqual(final.camera, .ready)
            XCTAssertEqual(final.pushed, 0)
            XCTAssertEqual(final.dropped, 0)
        }
    }

    /// Bug caught: the host holding the extension's sink stream open while no
    /// frames flow (no iPhone, disconnect, BUSY) — the extension stops its
    /// placeholder as soon as the sink streams, so Zoom would show black.
    func testSinkFollowsStreamingStateOnly() {
        for st in [LinkState.noDevice, .waiting, .starting, .incompatible, .busy] {
            XCTAssertFalse(CameraPipeline.sinkShouldBeConnected(link: st), "\(st)")
        }
        XCTAssertTrue(CameraPipeline.sinkShouldBeConnected(link: .streaming))
    }

    /// Bug caught: a status line with spaces inside a token breaks the
    /// `key=value` grep that install-local.sh and vcam-test.sh rely on.
    func testStatusLineTokensHaveNoSpaces() {
        let st = PipelineStatus(link: .waiting, camera: .waitingForUser, resolution: "-", fps: 0)
        XCTAssertEqual(st.line, "link=waiting camera=waiting-for-user res=- fps=0.0 "
            + "received=0 pushed=0 dropped=0 no-consumer=false")
    }
}
