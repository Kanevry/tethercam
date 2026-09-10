// SPDX-License-Identifier: MIT
// Receiver.swift
// TetherCam for macOS: IUCM client (PROTOCOL.md section 5). Connects to the phone,
// runs HELLO -> START -> CONFIG -> VIDEO..., keeps the link alive with PING and
// reconnects on every failure. Behaviour mirrors the OBS plugin's worker thread
// so the two receivers fail the same way in front of the same phone.

import CoreVideo
import Darwin
import Foundation
import IucmProtocol
import TetherCamContract

/// One receiver = one dedicated background thread. All callbacks fire on that
/// thread (or on VideoToolbox's decode thread for `onFrame`); return quickly.
///
/// `onFrame` hands over a CVPixelBuffer that is only retained by the receiver for
/// the duration of the callback: a consumer that needs it later must retain it
/// (`CVPixelBufferRetain` or a Swift strong reference) before returning.
public final class Receiver: @unchecked Sendable {

    public var onState: (@Sendable (LinkState) -> Void)?
    /// Fires on every CONFIG whose geometry changed: (width, height, fps).
    public var onConfig: (@Sendable (Int, Int, Int) -> Void)?
    /// Decoded frame (scaled to the contract format when `scaleToContract`) and its
    /// capture pts in microseconds.
    public var onFrame: (@Sendable (CVPixelBuffer, Int64) -> Void)?
    public var onStats: (@Sendable (ReceiverStats) -> Void)?
    /// Diagnostic log lines; nil drops them.
    public var onLog: (@Sendable (String) -> Void)?

    public private(set) var config: ReceiverConfig

    private let lock = NSLock()
    private var thread: Thread?
    private var running = false
    private var wakePipe: [Int32] = [-1, -1]
    private var fd: Int32 = -1
    private var state: LinkState = .noDevice
    private let joined = DispatchSemaphore(value: 0)

    // Per-session state (receiver thread only).
    private var parser = IucmFrameParser()
    private var decoder: HevcDecoder?
    private var scaler: FrameScaler?
    private var lastConfig: ConfigMessage?
    private var pendingPings: [UInt64: UInt64] = [:]
    private var missedPongs = 0
    private var lastRttMs: Double?
    private var winFrames = 0, winBytes = 0, keyframes = 0

    public init(config: ReceiverConfig) {
        self.config = config
    }

    deinit {
        stop()
    }

    /// Current link state, safe from any thread.
    public var linkState: LinkState {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    /// Spawns the receiver thread. Idempotent.
    public func start() {
        lock.lock()
        if running { lock.unlock(); return }
        running = true
        // A stop() issued from the receiver thread itself cannot join, so the
        // thread's final signal stays in the semaphore; drain it or the next
        // stop() from outside would return before the new thread has exited.
        while joined.wait(timeout: .now()) == .success {}
        var pipeFds: [Int32] = [-1, -1]
        if pipe(&pipeFds) == 0 {
            wakePipe = pipeFds
            _ = fcntl(pipeFds[0], F_SETFL, O_NONBLOCK)
        }
        let t = Thread { [weak self] in
            self?.threadMain()
            self?.joined.signal()
        }
        t.name = "TetherCam.Receiver"
        t.qualityOfService = .userInteractive
        thread = t
        lock.unlock()
        t.start()
    }

    /// Stops the thread and joins it. Idempotent; safe to call from any thread
    /// except the receiver thread itself.
    public func stop() {
        lock.lock()
        guard running else { lock.unlock(); return }
        running = false
        if wakePipe[1] >= 0 {
            var one: UInt8 = 1
            _ = write(wakePipe[1], &one, 1)
        }
        let isSelf = Thread.current === thread
        lock.unlock()
        if !isSelf { joined.wait() }
        lock.lock()
        for i in 0..<2 where wakePipe[i] >= 0 { close(wakePipe[i]); wakePipe[i] = -1 }
        thread = nil
        lock.unlock()
    }

    private var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    private func setState(_ st: LinkState) {
        lock.lock()
        let changed = st != state
        state = st
        lock.unlock()
        if changed { onState?(st) }
    }

    private func log(_ s: String) { onLog?(s) }

    // MARK: - Outer loop: connect, session, backoff

    private func threadMain() {
        var failures = 0
        while isRunning {
            let result = Transport.connect(config.endpoint)
            switch result {
            case .failure(let f):
                setState(f.deviceCount > 0 ? .waiting : .noDevice)
                let ms = ReceiverConfig.backoffMilliseconds(failures: failures)
                failures += 1
                log("connect attempt \(failures) failed (\(f.message)), retry in \(ms) ms")
                sleepInterruptible(ms: ms)
                continue
            case .success(let c):
                failures = 0
                fd = c.fd
                Transport.tuneSocket(fd, sendTimeoutMs: config.sendTimeoutMs)
                setState(.starting)
                log("connected to \(c.peer)")
                let outcome = runSession(peer: c.peer)
                closeSession()
                switch outcome {
                case .peerClosed:
                    sleepInterruptible(ms: Int(config.peerClosedDelay * 1000))
                case .fatal(let st):
                    setState(st)
                    sleepInterruptible(ms: Int(config.fatalRetryDelay * 1000))
                case .reconnect, .stopped:
                    break
                }
            }
        }
        closeSession()
    }

    private enum SessionOutcome {
        case stopped
        case reconnect
        case peerClosed
        case fatal(LinkState)
    }

    private func closeSession() {
        if fd >= 0 { close(fd); fd = -1 }
        decoder?.close()
        decoder = nil
        scaler = nil
        lastConfig = nil
        parser = IucmFrameParser()
        pendingPings.removeAll()
        missedPongs = 0
        lastRttMs = nil
        winFrames = 0; winBytes = 0; keyframes = 0
    }

    /// Sleeps up to `ms`, returning early when stop() pokes the wake pipe.
    private func sleepInterruptible(ms: Int) {
        guard ms > 0, isRunning else { return }
        let wake = wakePipe[0]
        if wake < 0 {
            usleep(useconds_t(ms * 1000))
            return
        }
        var pfd = pollfd(fd: wake, events: Int16(POLLIN), revents: 0)
        _ = poll(&pfd, 1, Int32(ms))
    }

    // MARK: - Session

    private func send(_ msg: IucmMessage) throws {
        try Transport.sendAll(fd, try IucmCodec.encode(msg))
    }

    private static func nowUs() -> UInt64 { DispatchTime.now().uptimeNanoseconds / 1000 }

    private func runSession(peer: String) -> SessionOutcome {
        let startUs = Self.nowUs()
        var helloUs: UInt64 = 0
        var started = false
        var lastPingUs: UInt64 = 0
        var lastReportUs = startUs
        var buf = [UInt8](repeating: 0, count: 1 << 16)

        while isRunning {
            var fds = [pollfd(fd: fd, events: Int16(POLLIN), revents: 0)]
            if wakePipe[0] >= 0 { fds.append(pollfd(fd: wakePipe[0], events: Int16(POLLIN), revents: 0)) }
            let rc = fds.withUnsafeMutableBufferPointer { poll($0.baseAddress, nfds_t($0.count), 100) }
            if rc < 0 && errno != EINTR { return .reconnect }
            if !isRunning { return .stopped }

            if rc > 0 && (fds[0].revents & Int16(POLLIN | POLLHUP | POLLERR)) != 0 {
                let n = read(fd, &buf, buf.count)
                if n == 0 { log("peer closed"); return .peerClosed }
                if n < 0 {
                    if errno != EINTR && errno != EAGAIN {
                        log("read failed: \(String(cString: strerror(errno)))")
                        return .reconnect
                    }
                } else {
                    let msgs: [IucmMessage]
                    do { msgs = try parser.append(Data(buf[0..<n])) } catch {
                        log("framing error: \(error)")
                        return .reconnect
                    }
                    for msg in msgs {
                        switch handle(msg, started: &started) {
                        case .none: break
                        case .some(let out): return out
                        }
                        if started && helloUs == 0 { helloUs = Self.nowUs() }
                    }
                }
            }

            let t = Self.nowUs()
            if !started {
                if t - startUs >= UInt64(config.helloTimeout * 1e6) {
                    log("no HELLO within \(config.helloTimeout) s, reconnecting")
                    return .reconnect
                }
            } else {
                if lastConfig == nil && t - helloUs >= UInt64(config.configTimeout * 1e6) {
                    log("no CONFIG within \(config.configTimeout) s, reconnecting")
                    return .reconnect
                }
                if t - lastPingUs >= UInt64(config.pingInterval * 1e6) {
                    lastPingUs = t
                    if missedPongs >= config.maxMissedPongs {
                        log("\(missedPongs) missed PONG, reconnecting")
                        return .reconnect
                    }
                    missedPongs += 1
                    pendingPings[t] = t
                    do { try send(.ping(t)) } catch {
                        log("sending PING failed: \(error)")
                        return .reconnect
                    }
                }
                if t - lastReportUs >= 1_000_000 {
                    let dt = Double(t - lastReportUs) / 1e6
                    onStats?(ReceiverStats(framesPerSecond: Double(winFrames) / dt,
                                           kilobitsPerSecond: Double(winBytes) * 8 / 1000 / dt,
                                           keyframes: keyframes,
                                           decodeErrors: decoder?.totalErrors ?? 0,
                                           lastPingRttMs: lastRttMs,
                                           peer: peer,
                                           scalerDrops: scaler?.droppedAtAllocationThreshold ?? 0))
                    winFrames = 0; winBytes = 0
                    lastReportUs = t
                }
            }
        }
        return .stopped
    }

    /// Returns a session outcome when the message ends the session, nil otherwise.
    private func handle(_ msg: IucmMessage, started: inout Bool) -> SessionOutcome? {
        switch msg {
        case .hello(let h):
            guard h.version >> 8 == 1 else {
                log("unsupported protocol major \(h.version >> 8), sending ERROR 5")
                try? send(.error(ErrorMessage(.versionUnsupported, "major")))
                return .fatal(.incompatible)
            }
            let camId: UInt8
            if let wanted = config.cameraId, h.cameras.contains(where: { $0.id == wanted }) {
                camId = wanted
            } else {
                camId = h.cameras.first?.id ?? 0
            }
            // CLIENT_INFO (0x04) names this receiver to the phone. It goes out
            // after HELLO and before START (PROTOCOL.md 4.11). A 1.0/1.1 app skips
            // the unknown type by `length`, so failing to send it must not end the
            // session: log and stream on.
            do {
                try send(.clientInfo(ClientInfoMessage(kind: .macApp, name: config.clientName,
                                                       version: config.clientVersion)))
            } catch {
                log("sending CLIENT_INFO failed (non-fatal): \(error)")
            }
            let start = StartMessage(cameraId: camId, width: config.width, height: config.height,
                                     fps: config.fps, bitrateKbps: config.bitrateKbps,
                                     flags: config.startFlags)
            do { try send(.start(start)) } catch {
                log("sending START failed: \(error)")
                return .reconnect
            }
            started = true
            log("HELLO from \(h.deviceName) (app \(h.appVersion), \(h.cameras.count) cameras), START camera \(camId)")
            return nil

        case .config(let c):
            let same = lastConfig.map { $0.width == c.width && $0.height == c.height
                && $0.fps == c.fps && $0.hvcc == c.hvcc } ?? false
            if !same {
                decoder?.close()
                do {
                    let d = try HevcDecoder(hvcC: c.hvcc, width: Int(c.width), height: Int(c.height))
                    d.onFrame = { [weak self] pixelBuffer, ptsUs in
                        self?.deliver(pixelBuffer, ptsUs: ptsUs)
                    }
                    decoder = d
                } catch {
                    log("decoder init failed: \(error)")
                    return .fatal(.incompatible)
                }
                if config.scaleToContract, scaler == nil {
                    scaler = try? FrameScaler()
                }
                let geometryChanged = lastConfig.map { $0.width != c.width || $0.height != c.height || $0.fps != c.fps } ?? true
                lastConfig = c
                if geometryChanged { onConfig?(Int(c.width), Int(c.height), Int(c.fps)) }
                log("CONFIG \(c.width)x\(c.height)@\(c.fps), hvcC \(c.hvcc.count) bytes")
            }
            setState(.streaming)
            return nil

        case .video(let v):
            winFrames += 1
            winBytes += v.nalData.count
            if v.isKeyframe { keyframes += 1 }
            _ = decoder?.decode(nalData: v.nalData, ptsUs: Int64(v.ptsUs), keyframe: v.isKeyframe)
            return nil

        case .pong(let ts):
            if let sent = pendingPings.removeValue(forKey: ts) {
                lastRttMs = Double(Self.nowUs() &- sent) / 1000
            }
            missedPongs = 0
            return nil

        case .ping(let ts):
            try? send(.pong(ts))
            return nil

        case .error(let e):
            switch IucmErrorCode(rawValue: e.code) {
            case .micDenied:
                log("phone reports MIC_DENIED (\(e.text)); video continues")
                return nil
            case .busy:
                log("phone is BUSY: \(e.text)")
                return .fatal(.busy)
            default:
                log("phone ERROR \(e.code): \(e.text)")
                return .fatal(.incompatible)
            }

        case .stats, .audioConfig, .audio, .start, .stop, .clientInfo:
            return nil
        }
    }

    private func deliver(_ pixelBuffer: CVPixelBuffer, ptsUs: Int64) {
        guard let onFrame else { return }
        if let scaler {
            if let out = scaler.scale(pixelBuffer) { onFrame(out, ptsUs) }
        } else {
            onFrame(pixelBuffer, ptsUs)
        }
    }
}
