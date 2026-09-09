// SPDX-License-Identifier: MIT
import Foundation
import XCTest
@testable import TetherCamCore

final class PipelineTests: XCTestCase {

    /// Bug caught: a pipeline that refuses to receive while the Camera Extension
    /// is absent (connect() throwing deviceNotFound must not stop the receiver),
    /// or one that "pushes" frames into a sink that is not connected.
    func testLiveSimStreamsWithoutSink() throws {
        let sim = try SimHarness(port: 7982)
        defer { sim.stop() }

        let pipeline = CameraPipeline(endpoint: .tcp(host: "127.0.0.1", port: 7982))
        let statuses = Locked<[PipelineStatus]>([])
        pipeline.onStatus = { st in statuses.with { $0.append(st) } }
        pipeline.start()
        defer { pipeline.stop() }

        let deadline = Date().addingTimeInterval(6)
        while pipeline.currentStatus.received < 10 && Date() < deadline { usleep(20_000) }

        let final = pipeline.currentStatus
        XCTAssertTrue(statuses.value.map(\.link).contains(.streaming), "statuses: \(statuses.value.map(\.line))")
        XCTAssertGreaterThanOrEqual(final.received, 10, "frames received: \(final.received)")
        XCTAssertEqual(final.resolution, "1920x1080@30")

        if CMIOSink.isDevicePresent() {
            // Extension enabled on this machine: frames must actually reach the sink.
            XCTAssertEqual(final.camera, .ready)
            XCTAssertGreaterThan(final.pushed + final.dropped, 0)
        } else {
            XCTAssertNotEqual(final.camera, .ready)
            XCTAssertEqual(final.pushed, 0)
            XCTAssertEqual(final.dropped, 0)
        }
    }

    /// Bug caught: a status line with spaces inside a token breaks the
    /// `key=value` grep that install-local.sh and vcam-test.sh rely on.
    func testStatusLineTokensHaveNoSpaces() {
        let st = PipelineStatus(link: .waiting, camera: .waitingForUser, resolution: "-", fps: 0)
        XCTAssertEqual(st.line, "link=waiting camera=waiting-for-user res=- fps=0.0 pushed=0 dropped=0")
    }
}
