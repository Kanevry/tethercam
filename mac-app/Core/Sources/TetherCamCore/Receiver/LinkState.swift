// SPDX-License-Identifier: MIT
// LinkState.swift
// TetherCam for macOS: user-visible link state of the receiver, mirroring the
// OBS plugin's status line so both products tell the same story.

import Foundation

public enum LinkState: Equatable, Sendable {
    /// No iPhone on the cable (usbmux lists zero devices).
    case noDevice
    /// Device seen but port 7878 refuses: the app is not in the foreground.
    case waiting
    /// Connected, HELLO/START/CONFIG handshake in progress.
    case starting
    /// CONFIG received, frames flowing.
    case streaming
    /// Peer answered ERROR (other than BUSY/MIC_DENIED) or speaks another major version.
    case incompatible
    /// Peer answered ERROR 1 BUSY: another receiver holds the camera.
    case busy
}

/// Tunables of the receiver. Defaults mirror the OBS plugin; tests shorten the
/// deadlines to keep the suite fast.
public struct ReceiverConfig: Equatable, Sendable {
    public var endpoint: Endpoint
    /// Camera id from HELLO to request; nil picks the first camera the phone lists.
    public var cameraId: UInt8?
    public var width: UInt16 = 1920
    public var height: UInt16 = 1080
    public var fps: UInt16 = 30
    public var bitrateKbps: UInt32 = 12_000
    /// Always sent as flags 0: the virtual camera carries no audio (PROTOCOL.md 4.2).
    public var startFlags: UInt8 = 0
    public var helloTimeout: TimeInterval = 5
    public var configTimeout: TimeInterval = 5
    public var pingInterval: TimeInterval = 2
    public var maxMissedPongs: Int = 3
    public var sendTimeoutMs: Int = 200
    /// Pause after the peer closed the socket before reconnecting.
    public var peerClosedDelay: TimeInterval = 0.25
    /// Pause after a fatal answer (BUSY, incompatible) before the next attempt.
    public var fatalRetryDelay: TimeInterval = 5
    /// Route decoded frames through FrameScaler to the contract format before onFrame.
    public var scaleToContract: Bool = true
    /// CLIENT_INFO `name` (PROTOCOL.md 4.11); the phone shows it as the connected receiver.
    public var clientName: String = "TetherCam for Mac"
    /// CLIENT_INFO `version`; the host fills this from `Bundle.main`.
    public var clientVersion: String = "0"

    public init(endpoint: Endpoint) {
        self.endpoint = endpoint
    }

    /// Connect backoff ladder: 1 s, 2 s, 3 s, 4 s, 5 s, 5 s, ... (`failures` counts
    /// the attempts that already failed, starting at 0 for the first retry).
    public static func backoffMilliseconds(failures: Int) -> Int {
        min(5000, 1000 + 1000 * max(0, failures))
    }
}

/// Snapshot of link telemetry, published about once per second while streaming.
public struct ReceiverStats: Equatable, Sendable {
    public var framesPerSecond: Double
    public var kilobitsPerSecond: Double
    public var keyframes: Int
    public var decodeErrors: Int
    public var lastPingRttMs: Double?
    public var peer: String
    /// Frames the scaler could not allocate a pool buffer for since the session
    /// started (the consumer still holds every buffer). Cumulative, not per window.
    public var scalerDrops: UInt64 = 0
}
