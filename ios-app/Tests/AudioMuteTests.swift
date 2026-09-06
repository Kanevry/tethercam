import XCTest
@testable import TetherCam

/// Mute switch (GitLab #5): the STATS flag bits and the frame gate that drops
/// muted access units without breaking the pts chain.
final class AudioMuteTests: XCTestCase {

    // MARK: - STATS flags

    func testAudioFlagsSetOnlyBitsFourAndFive() {
        XCTAssertEqual(UsbServer.audioFlags(active: false, muted: false), 0)
        XCTAssertEqual(UsbServer.audioFlags(active: true, muted: false),
                       DeviceStats.flagAudioActive)
        XCTAssertEqual(UsbServer.audioFlags(active: false, muted: true),
                       DeviceStats.flagAudioMuted)
        XCTAssertEqual(UsbServer.audioFlags(active: true, muted: true),
                       DeviceStats.flagAudioActive | DeviceStats.flagAudioMuted)
        // Bit 4 is 0x10 and bit 5 is 0x20; the leveller bits below must stay clear.
        XCTAssertEqual(UsbServer.audioFlags(active: true, muted: true), 0x30)
    }

    func testAudioFlagsLeaveTheLevellerFlagsUntouched() {
        let base = DeviceStats.flagAutoRotation | DeviceStats.flagHorizonLeveling
            | DeviceStats.flagOversampling | DeviceStats.flagFlatHold
        let merged = base | UsbServer.audioFlags(active: true, muted: true)
        XCTAssertEqual(merged & 0x0F, base)
        XCTAssertEqual(merged, 0x3F)
    }

    // MARK: - Frame gate

    /// pts of the n-th access unit since the anchor. Same integer arithmetic as
    /// the encoder: dividing only once keeps the chain drift-free at 48 kHz,
    /// where one packet is 21333.33 us long.
    private func pts(_ n: UInt64, anchor: UInt64 = 0) -> UInt64 {
        anchor + n * UInt64(AudioCapture.framesPerPacket) * 1_000_000
            / UInt64(AudioCapture.outputSampleRate)
    }

    func testMutedPacketsAreDropped() {
        var gate = AudioCapture.MuteGate()
        var sent: [UInt64] = []
        for i in 0..<10 {
            let muted = (3..<7).contains(i)
            if let pts = gate.next(anchorPtsUs: 1_000, muted: muted) { sent.append(pts) }
        }
        XCTAssertEqual(sent.count, 6)
        XCTAssertEqual(gate.emittedPackets, 10)
    }

    /// The bug this guards: dropping muted packets *and* their counter increment
    /// would restart the pts chain at the anchor on unmute, so the receiver would
    /// see audio jump backwards by the length of the mute.
    func testPtsStaysMonotoneAndOnTheTimelineAcrossAnUnmute() {
        var gate = AudioCapture.MuteGate()
        let anchor: UInt64 = 5_000
        var sent: [UInt64] = []
        for i in 0..<8 {
            if let pts = gate.next(anchorPtsUs: anchor, muted: (2..<5).contains(i)) {
                sent.append(pts)
            }
        }
        for (a, b) in zip(sent, sent.dropFirst()) {
            XCTAssertLessThan(a, b, "pts must rise strictly: \(sent)")
        }
        // First packet after the mute is the sixth on the timeline, not the third.
        XCTAssertEqual(sent[2], pts(5, anchor: anchor))
        XCTAssertEqual(sent[2] - sent[1], pts(5) - pts(1))
    }

    func testUnmutedChainMatchesThePacketRate() {
        var gate = AudioCapture.MuteGate()
        for i in 0..<4 {
            XCTAssertEqual(gate.next(anchorPtsUs: 0, muted: false), pts(UInt64(i)))
        }
    }

    func testResetStartsANewTakeAtTheAnchor() {
        var gate = AudioCapture.MuteGate()
        _ = gate.next(anchorPtsUs: 100, muted: false)
        _ = gate.next(anchorPtsUs: 100, muted: true)
        gate.reset()
        XCTAssertEqual(gate.emittedPackets, 0)
        XCTAssertEqual(gate.next(anchorPtsUs: 900, muted: false), 900)
    }

    // MARK: - Resync

    /// The bug this guards: the pts chain is pure arithmetic from the anchor, so
    /// a 500 ms hole in the microphone stream (interruption, call, dropped
    /// buffers) used to leave audio permanently 500 ms behind the picture.
    func testGapReanchorsThePtsChainForward() {
        let anchor: UInt64 = 1_000_000
        let emitted: UInt64 = 10
        let expected = pts(emitted, anchor: anchor)
        let actual = expected + 500_000
        let newAnchor = AudioCapture.resyncAnchor(anchorPtsUs: anchor,
                                                  emittedPackets: emitted,
                                                  actualPtsUs: actual)
        XCTAssertEqual(newAnchor, actual)
        XCTAssertGreaterThan(newAnchor!, pts(emitted - 1, anchor: anchor))
    }

    func testJitterWithinOnePacketKeepsTheAnchor() {
        let anchor: UInt64 = 1_000_000
        let emitted: UInt64 = 4
        let expected = pts(emitted, anchor: anchor)
        for delta in [UInt64(0), 5_000, AudioCapture.packetDurationUs] {
            XCTAssertNil(AudioCapture.resyncAnchor(anchorPtsUs: anchor,
                                                   emittedPackets: emitted,
                                                   actualPtsUs: expected + delta))
            XCTAssertNil(AudioCapture.resyncAnchor(anchorPtsUs: anchor,
                                                   emittedPackets: emitted,
                                                   actualPtsUs: expected - delta))
        }
    }

    /// A backwards jump must never rewind the wire pts: the new anchor stays at
    /// least one packet past the last access unit that already went out.
    func testBackwardsJumpNeverMovesThePtsBackwards() {
        let anchor: UInt64 = 1_000_000
        let emitted: UInt64 = 10
        let lastSent = pts(emitted - 1, anchor: anchor)
        let newAnchor = AudioCapture.resyncAnchor(anchorPtsUs: anchor,
                                                  emittedPackets: emitted,
                                                  actualPtsUs: anchor - 500_000)
        XCTAssertNotNil(newAnchor)
        XCTAssertGreaterThanOrEqual(newAnchor!, lastSent + AudioCapture.packetDurationUs)
        // The chain continues from the new anchor without a step backwards.
        var gate = AudioCapture.MuteGate()
        XCTAssertEqual(gate.next(anchorPtsUs: newAnchor!, muted: false), newAnchor!)
        XCTAssertGreaterThan(newAnchor!, lastSent)
    }

    /// PCM already queued belongs to the time before this buffer, so it must not
    /// register as drift.
    func testQueuedPcmIsNotMistakenForDrift() {
        let anchor: UInt64 = 0
        let pending = AudioCapture.packetDurationUs * 2
        let onTime = pts(3, anchor: anchor) + pending
        XCTAssertNil(AudioCapture.resyncAnchor(anchorPtsUs: anchor,
                                               emittedPackets: 3,
                                               actualPtsUs: onTime,
                                               pendingUs: pending))
        XCTAssertNotNil(AudioCapture.resyncAnchor(anchorPtsUs: anchor,
                                                  emittedPackets: 3,
                                                  actualPtsUs: onTime,
                                                  pendingUs: 0))
    }

    // MARK: - Error latch

    /// The bug this guards: `drain()` reported `encoderFailed` per PCM buffer
    /// (~50 per second), so a single broken converter produced ~50 ERROR frames
    /// per second on the wire.
    func testRepeatedEncoderFailuresReportOnce() {
        let audio = AudioCapture()
        var codes: [IucmErrorCode] = []
        audio.onError = { codes.append($0) }
        audio.latchEncoderFailure()
        audio.latchEncoderFailure()
        audio.latchEncoderFailure()
        XCTAssertEqual(codes, [.encoderFailed])
    }

    /// After a successful converter rebuild the latch is re-armed, so a later
    /// breakage is reported again.
    func testEncoderFailureIsReportedAgainAfterARebuild() {
        let audio = AudioCapture()
        var codes: [IucmErrorCode] = []
        audio.onError = { codes.append($0) }
        audio.latchEncoderFailure()
        audio.latchEncoderFailure()
        audio.clearEncoderFailure()
        audio.latchEncoderFailure()
        XCTAssertEqual(codes, [.encoderFailed, .encoderFailed])
    }

    // MARK: - Switch plumbing

    func testMuteSwitchIsReadableFromTheCaptureEngineWithoutHardware() {
        let audio = AudioCapture()
        XCTAssertFalse(audio.isMuted)
        XCTAssertFalse(audio.micDenied)
        audio.isMuted = true
        XCTAssertTrue(audio.isMuted)
    }
}
