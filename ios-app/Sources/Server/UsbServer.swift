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
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
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
        for a in actions {
            switch a {
            case let .send(msg, id):
                send(msg, to: id)
            case let .close(id):
                connections[id]?.cancel()
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

    private func send(_ msg: IucmMessage, to id: UInt64) {
        guard let conn = connections[id] else { return }
        conn.send(content: IucmCodec.encode(msg), completion: .idempotent)
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
