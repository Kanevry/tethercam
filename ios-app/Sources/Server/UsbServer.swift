import Foundation
import Network
import UIKit

/// TCP listener on port 7878. Over a USB cable this port is reached through the
/// Mac-side usbmux tunnel; no Wi-Fi interface is required.
///
/// All connection bookkeeping runs on one serial queue; the pure decision logic
/// lives in `ServerStateMachine` so it stays unit-testable.
public final class UsbServer {

    public struct Stats {
        public var connected = false
        public var streaming = false
        public var fps: Double = 0
        public var kbps: Double = 0
        /// Format the camera actually delivers, 0 while nothing is running.
        /// The checklist card in the UI shows this, so it must not be the
        /// requested format but the one in effect.
        public var width: Int = 0
        public var height: Int = 0
        public var targetFps: Int = 0
    }

    private let queue = DispatchQueue(label: "at.gotzendorfer.usbcam.server")
    private var listener: NWListener?
    private var connections: [UInt64: NWConnection] = [:]
    private var parsers: [UInt64: IucmFrameParser] = [:]
    private var nextId: UInt64 = 1
    private var machine: ServerStateMachine
    private var tickTimer: DispatchSourceTimer?

    private let capture: CaptureEngine
    private let encoder = HevcEncoder()

    // Rolling counters for the status line.
    private var frameCount = 0
    private var byteCount = 0
    private var windowStart = Date()

    public private(set) var stats = Stats()
    public var onStats: ((Stats) -> Void)?
    public var onListenerState: ((String) -> Void)?

    public init(capture: CaptureEngine) {
        self.capture = capture
        let name = UIDevice.current.name
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
        machine = ServerStateMachine(deviceName: name, appVersion: version,
                                     cameras: capture.descriptors)
        encoder.onMessage = { [weak self] msg in self?.queue.async { self?.emit(msg) } }
        encoder.onError = { [weak self] _ in
            self?.queue.async {
                self?.apply(self?.machine.handle(.captureFailed(.encoderFailed,
                                                                text: "encoder failed")) ?? [])
            }
        }
        capture.onSampleBuffer = { [weak self] sb in self?.encoder.encode(sb) }
    }

    // MARK: - Lifecycle

    public func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                (params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options)?
                    .noDelay = true
                let l = try NWListener(using: params,
                                       on: NWEndpoint.Port(rawValue: Iucm.defaultPort)!)
                l.stateUpdateHandler = { [weak self] state in
                    self?.onListenerState?("\(state)")
                }
                l.newConnectionHandler = { [weak self] c in self?.accept(c) }
                l.start(queue: queue)
                listener = l
                startTicking()
            } catch {
                onListenerState?("failed: \(error)")
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            tickTimer?.cancel(); tickTimer = nil
            for (_, c) in connections { c.cancel() }
            connections.removeAll(); parsers.removeAll()
            listener?.cancel(); listener = nil
            capture.stop(); encoder.stop()
        }
    }

    private func startTicking() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.apply(self.machine.handle(.tick(nowUs: Self.nowUs())))
            self.refreshStats()
            self.sendStats()
        }
        t.resume()
        tickTimer = t
    }

    // MARK: - Connections

    private func accept(_ conn: NWConnection) {
        let id = nextId; nextId &+= 1
        connections[id] = conn
        parsers[id] = IucmFrameParser()
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .cancelled, .failed:
                self.queue.async {
                    self.connections[id] = nil
                    self.parsers[id] = nil
                    self.apply(self.machine.handle(.connectionClosed(id: id)))
                }
            default: break
            }
        }
        conn.start(queue: queue)
        receive(id)
        apply(machine.handle(.connectionAccepted(id: id, nowUs: Self.nowUs())))
    }

    private func receive(_ id: UInt64) {
        guard let conn = connections[id] else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty, let parser = self.parsers[id] {
                do {
                    for msg in try parser.feedMessages(data) {
                        self.apply(self.machine.handle(.message(msg, nowUs: Self.nowUs())))
                    }
                } catch {
                    // Broken framing beyond resync: drop the connection (spec 8).
                    conn.cancel()
                    return
                }
            }
            if isComplete || error != nil {
                conn.cancel()
                return
            }
            self.receive(id)
        }
    }

    // MARK: - Action application

    private func apply(_ actions: [ServerStateMachine.Action]) {
        for (i, a) in actions.enumerated() {
            switch a {
            case let .send(msg, id):
                // A `.close` later in the same batch (BUSY, teardown) must not
                // race the send: cancelling right after queueing drops the bytes
                // and the Mac only sees the socket close. Close in the send
                // completion instead.
                send(msg, to: id, thenClose: Self.batch(actions, closes: id, after: i))
            case let .close(id):
                // Skip the abrupt cancel when a preceding send already scheduled
                // the graceful close for this connection.
                if !Self.batch(actions, sendsTo: id, before: i) {
                    connections[id]?.cancel()
                }
                connections[id] = nil
                parsers[id] = nil
            case let .startCapture(p):
                startCapture(p)
            case .stopCapture:
                capture.stop()
                encoder.stop()
            }
        }
        refreshStats()
    }

    private func startCapture(_ p: StartParams) {
        capture.start(p) { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .success:
                    let f = self.capture.activeFormat ?? (p.width, p.height, p.fps)
                    do {
                        try self.encoder.start(width: f.width, height: f.height,
                                               fps: f.fps, bitrateKbps: p.bitrateKbps)
                    } catch {
                        self.apply(self.machine.handle(
                            .captureFailed(.encoderFailed, text: "\(error)")))
                    }
                case let .failure(err):
                    let code: IucmErrorCode =
                        (err as? CaptureEngine.CaptureError) == .some(.denied)
                        ? .cameraDenied : .formatUnsupported
                    self.apply(self.machine.handle(.captureFailed(code, text: "\(err)")))
                }
            }
        }
    }

    private func emit(_ msg: IucmMessage) {
        guard let id = machine.activeConnection else { return }
        if case let .video(_, _, nal) = msg {
            frameCount += 1
            byteCount += nal.count
        }
        send(msg, to: id)
    }

    private func send(_ msg: IucmMessage, to id: UInt64, thenClose: Bool = false) {
        guard let conn = connections[id] else { return }
        if thenClose {
            conn.send(content: IucmCodec.encode(msg),
                      completion: .contentProcessed { _ in conn.cancel() })
        } else {
            conn.send(content: IucmCodec.encode(msg), completion: .idempotent)
        }
    }

    /// True when `actions` closes `id` at an index after `i`.
    static func batch(_ actions: [ServerStateMachine.Action],
                      closes id: UInt64, after i: Int) -> Bool {
        actions[(i + 1)...].contains {
            if case let .close(cid) = $0 { return cid == id }
            return false
        }
    }

    /// True when `actions` sends to `id` at an index before `i`.
    static func batch(_ actions: [ServerStateMachine.Action],
                      sendsTo id: UInt64, before i: Int) -> Bool {
        actions[..<i].contains {
            if case let .send(_, sid) = $0 { return sid == id }
            return false
        }
    }

    /// STATS (`0x12`) once per second, whenever a receiver is attached — also
    /// while idle. Orientation and leveller state is exactly what is unreadable
    /// from the Mac otherwise, and it is most needed *before* streaming starts.
    /// Fire-and-forget: an old receiver that predates 0x12 skips the unknown type
    /// per PROTOCOL.md section 2, so this is safe to send unconditionally.
    private func sendStats() {
        guard let id = machine.activeConnection else { return }
        send(.stats(capture.statsSnapshot()), to: id)
    }

    private func refreshStats() {
        let elapsed = Date().timeIntervalSince(windowStart)
        if elapsed >= 1 {
            stats.fps = Double(frameCount) / elapsed
            stats.kbps = Double(byteCount) * 8 / 1000 / elapsed
            frameCount = 0; byteCount = 0; windowStart = Date()
        }
        stats.connected = machine.activeConnection != nil
        stats.streaming = machine.isStreaming
        if let f = capture.activeFormat {
            stats.width = Int(f.width); stats.height = Int(f.height); stats.targetFps = Int(f.fps)
        } else {
            stats.width = 0; stats.height = 0; stats.targetFps = 0
        }
        let s = stats
        DispatchQueue.main.async { [weak self] in self?.onStats?(s) }
    }

    static func nowUs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000_000)
    }
}

extension CaptureEngine.CaptureError: Equatable {
    public static func == (a: CaptureEngine.CaptureError, b: CaptureEngine.CaptureError) -> Bool {
        switch (a, b) {
        case (.denied, .denied), (.cannotAddInput, .cannotAddInput),
             (.cannotAddOutput, .cannotAddOutput): return true
        case let (.noSuchCamera(x), .noSuchCamera(y)): return x == y
        default: return false
        }
    }
}
