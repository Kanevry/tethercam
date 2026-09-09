// SPDX-License-Identifier: MIT
// CameraPipeline.swift
// TetherCam for macOS: glues one Receiver (phone -> decoded NV12 frames) to one
// CMIOSink (frames -> Camera Extension). This is the whole host app minus UI.

import CoreMedia
import CoreVideo
import Foundation

/// Snapshot of everything the menu bar / headless log wants to show.
public struct PipelineStatus: Equatable, @unchecked Sendable {
    public var link: LinkState
    public var camera: CameraStatus
    /// "1920x1080@30" from the last CONFIG, "-" before the first one.
    public var resolution: String
    /// Decoded frames per second over the receiver's last 1 s window.
    public var fps: Double
    /// Frames decoded since start (pushed or not).
    public var received: UInt64
    /// Frames handed to the extension's sink queue.
    public var pushed: UInt64
    /// Frames dropped by the sink (queue full, not connected counts as neither).
    public var dropped: UInt64

    public init(link: LinkState = .noDevice, camera: CameraStatus = .extensionMissing,
                resolution: String = "-", fps: Double = 0,
                received: UInt64 = 0, pushed: UInt64 = 0, dropped: UInt64 = 0) {
        self.link = link
        self.camera = camera
        self.resolution = resolution
        self.fps = fps
        self.received = received
        self.pushed = pushed
        self.dropped = dropped
    }

    /// One-line form used by `--headless` and the tests:
    /// `link=streaming camera=ready res=1920x1080@30 fps=30.0 pushed=12 dropped=0`.
    public var line: String {
        "link=\(link.shortName) camera=\(camera.shortName) res=\(resolution) "
            + "fps=\(String(format: "%.1f", fps)) pushed=\(pushed) dropped=\(dropped)"
    }
}

public extension LinkState {
    /// Stable machine-readable token (no spaces) for logs.
    var shortName: String {
        switch self {
        case .noDevice: return "no-device"
        case .waiting: return "waiting"
        case .starting: return "starting"
        case .streaming: return "streaming"
        case .incompatible: return "incompatible"
        case .busy: return "busy"
        }
    }
}

public extension CameraStatus {
    /// Stable machine-readable token (no spaces) for logs.
    var shortName: String {
        switch self {
        case .extensionMissing: return "missing"
        case .waitingForUser: return "waiting-for-user"
        case .ready: return "ready"
        case .error: return "error"
        }
    }
}

/// Owns the receiver and the sink. Thread model: all bookkeeping runs on a
/// private serial queue; `onStatus` fires on that queue (hop to main yourself).
/// `onFrame` from the receiver is handled inline on the decoder thread because
/// the sink is thread-safe and drop-on-full, so nothing there can block.
public final class CameraPipeline: @unchecked Sendable {

    /// Interval between sink connect attempts while the link streams but the
    /// extension is absent: the user may approve it in System Settings while
    /// the app keeps running.
    public static let sinkRetryInterval: TimeInterval = 2

    /// The one decision behind the sink lifecycle: the host attaches to the
    /// extension's SINK stream only while frames actually flow. Any other link
    /// state leaves the sink stopped, so the extension shows its placeholder
    /// instead of black (no iPhone, disconnect, BUSY, incompatible).
    public static func sinkShouldBeConnected(link: LinkState) -> Bool {
        link == .streaming
    }

    public var onStatus: (@Sendable (PipelineStatus) -> Void)?
    /// Diagnostic lines from the receiver and the pipeline itself.
    public var onLog: (@Sendable (String) -> Void)?

    private let receiver: Receiver
    private let sink = CMIOSink()
    private let queue = DispatchQueue(label: "at.gotzendorfer.tethercam.pipeline")
    private let lock = NSLock()
    private var status = PipelineStatus()
    private var running = false
    private var retryGeneration = 0

    public init(endpoint: Endpoint) {
        receiver = Receiver(config: ReceiverConfig(endpoint: endpoint))
        receiver.onLog = { [weak self] line in self?.onLog?("receiver: \(line)") }
        receiver.onState = { [weak self] st in
            guard let self else { return }
            self.update { $0.link = st; if st != .streaming { $0.fps = 0 } }
            self.syncSink(link: st)
        }
        receiver.onConfig = { [weak self] w, h, f in
            self?.update { $0.resolution = "\(w)x\(h)@\(f)" }
        }
        receiver.onStats = { [weak self] stats in
            guard let self else { return }
            let (p, d) = (self.sink.pushedFrames, self.sink.droppedFrames)
            self.update { $0.fps = stats.framesPerSecond; $0.pushed = p; $0.dropped = d }
        }
        receiver.onFrame = { [weak self] buffer, _ in
            self?.handle(frame: buffer)
        }
    }

    /// Current snapshot (also delivered through `onStatus` on every change).
    public var currentStatus: PipelineStatus { lock.withLock { status } }

    /// Starts receiving immediately; the sink is connected once the link streams
    /// (see `sinkShouldBeConnected`).
    public func start() {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        retryGeneration += 1
        lock.unlock()
        // Probe once so the menu shows "install" / "approve" before any iPhone
        // shows up. probe() shells out to systemextensionsctl: keep it off the caller.
        queue.async { [weak self] in
            guard let self, self.lock.withLock({ self.running }), !self.sink.isConnected else { return }
            self.update { $0.camera = CameraStatus.probe() }
        }
        receiver.start()
    }

    /// Stops the receiver, disconnects the sink and cancels pending retries.
    public func stop() {
        lock.lock()
        guard running else { lock.unlock(); return }
        running = false
        retryGeneration += 1
        lock.unlock()
        receiver.stop()
        sink.disconnect()
        update { $0.link = .noDevice; $0.fps = 0 }
    }

    // MARK: - Sink

    /// Follows the link state (called on the receiver thread): streaming starts
    /// the connect/retry loop, anything else cancels it and stops the sink
    /// stream so the extension falls back to its placeholder.
    private func syncSink(link: LinkState) {
        lock.lock()
        guard running else { lock.unlock(); return }
        retryGeneration += 1   // cancels a pending retry in either direction
        let generation = retryGeneration
        lock.unlock()
        if Self.sinkShouldBeConnected(link: link) {
            queue.async { [weak self] in self?.tryConnectSink(generation: generation) }
        } else if sink.isConnected {
            sink.disconnect()
            onLog?("sink disconnected (link \(link.shortName)); the camera shows its placeholder")
        }
    }

    private func tryConnectSink(generation: Int) {
        guard lock.withLock({ running && retryGeneration == generation }) else { return }
        guard !sink.isConnected else { return }
        do {
            try sink.connect()
            onLog?("sink connected to the TetherCam camera")
            update { $0.camera = .ready }
            return
        } catch CMIOSinkError.deviceNotFound {
            // Expected while the extension is not (yet) enabled; probe explains why.
            let probed = CameraStatus.probe()
            update { $0.camera = probed }
        } catch {
            onLog?("sink connect failed: \(error)")
            update { $0.camera = .error("\(error)") }
        }
        queue.asyncAfter(deadline: .now() + Self.sinkRetryInterval) { [weak self] in
            self?.tryConnectSink(generation: generation)
        }
    }

    private func handle(frame: CVPixelBuffer) {
        lock.lock()
        status.received += 1
        lock.unlock()
        // PTS policy: the phone's pts is on its own capture clock; the extension
        // forwards whatever pts it gets and camera clients (Zoom, FaceTime, ffmpeg)
        // expect presentation times on the host clock. Frames are shown as soon as
        // they arrive anyway, so the host time at push is the correct pts: no
        // drift, no offset estimation, at most one frame of jitter.
        let host = CMClockGetTime(CMClockGetHostTimeClock())
        let hostUs = Int64(CMTimeGetSeconds(host) * 1_000_000)
        sink.push(frame, ptsUs: hostUs)
    }

    // MARK: - Status

    private func update(_ mutate: (inout PipelineStatus) -> Void) {
        lock.lock()
        let before = status
        mutate(&status)
        let after = status
        lock.unlock()
        if before != after { onStatus?(after) }
    }
}
