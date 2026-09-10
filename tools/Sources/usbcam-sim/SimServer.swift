import Foundation
import IucmProtocol
import Network

func log(_ message: String) {
    FileHandle.standardError.write(Data("[usbcam-sim] \(message)\n".utf8))
}

/// Sender-side simulator: speaks the IUCM protocol over TCP and streams a
/// VideoToolbox-encoded test pattern. Stands in for the iPhone app.
///
/// All state lives on one serial queue; VideoToolbox callbacks hop onto it.
final class SimServer {
    private let queue = DispatchQueue(label: "at.gotzendorfer.usbcam-sim")
    private let bindHost: String
    private let port: UInt16
    private let dumpPath: String?
    /// `--no-audio` sets this false; audio then stays off even if START asks for it.
    private let audioEnabled: Bool

    private var listener: NWListener?
    private var connection: NWConnection?
    private var parser = IucmFrameParser()

    private var renderer: TestPatternRenderer?
    private var encoder: HevcEncoder?
    private var frameTimer: DispatchSourceTimer?
    private var statusTimer: DispatchSourceTimer?

    private var frameIndex = 0
    private var streamStart: DispatchTime?
    private var lastPtsUs: UInt64 = 0
    private var sentHvcc: Data?
    private var activeFormat: (width: UInt16, height: UInt16, fps: UInt16)?
    private var pingArmed = false
    private var lastPingAt: DispatchTime?

    private var audioEncoder: AacToneEncoder?
    private var audioConfigSent = false
    private var audioFrameIndex = 0

    private var statFrames = 0
    private var statBytes = 0
    private var statKeyframes = 0
    private var dumpHandle: FileHandle?

    init(bindHost: String, port: UInt16, dumpPath: String?, audioEnabled: Bool = true) {
        self.bindHost = bindHost
        self.port = port
        self.dumpPath = dumpPath
        self.audioEnabled = audioEnabled
    }

    // MARK: - Lifecycle

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        if let tcp = params.defaultProtocolStack.internetProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw SimError.setupFailed("invalid port \(port)")
        }
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(bindHost), port: nwPort)

        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { log("listener failed: \(error)") }
        }
        listener.start(queue: queue)
        self.listener = listener

        if let dumpPath {
            FileManager.default.createFile(atPath: dumpPath, contents: nil)
            dumpHandle = FileHandle(forWritingAtPath: dumpPath)
            if dumpHandle == nil { throw SimError.setupFailed("cannot open dump file \(dumpPath)") }
            log("dumping Annex-B HEVC to \(dumpPath)")
        }

        startStatusTimer()
        log("listening on \(bindHost):\(port)")
    }

    // MARK: - Connections

    private func accept(_ conn: NWConnection) {
        guard connection == nil else {
            // Exactly one receiver at a time — the second one is told why and dropped.
            log("rejecting second connection with ERROR 1 BUSY")
            conn.start(queue: queue)
            let busy = (try? IucmCodec.encode(.error(ErrorMessage(.busy, "a receiver is already connected"))))
            conn.send(content: busy, completion: .contentProcessed { _ in conn.cancel() })
            return
        }

        connection = conn
        parser = IucmFrameParser()
        pingArmed = false
        lastPingAt = nil
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: log("receiver connected")
            case .failed(let e): log("connection failed: \(e)"); self?.dropConnection(reason: "failed")
            case .cancelled: self?.dropConnection(reason: "cancelled")
            default: break
            }
        }
        conn.start(queue: queue)
        send(.hello(HelloMessage(deviceName: Host.current().localizedName ?? "usbcam-sim",
                                 appVersion: SimVersion.string,
                                 cameras: [CameraInfo(id: 0, position: .back, name: "Simulator")])))
        receive(on: conn)
    }

    /// Latest CLIENT_INFO from the connected receiver, nil until one arrives (4.11).
    private(set) var receiverInfo: ClientInfoMessage?

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                log("receive error: \(error)")
                self.dropConnection(reason: "receive error")
                return
            }
            if let data, !data.isEmpty {
                do {
                    for message in try self.parser.append(data) { self.handle(message) }
                } catch {
                    log("protocol error: \(error) — closing")
                    self.dropConnection(reason: "protocol error")
                    return
                }
            }
            if isComplete {
                self.dropConnection(reason: "peer closed")
                return
            }
            guard self.connection === conn else { return }
            self.receive(on: conn)
        }
    }

    private func dropConnection(reason: String) {
        guard connection != nil else { return }
        log("dropping connection (\(reason))")
        stopStreaming()
        connection?.cancel()
        connection = nil
        pingArmed = false
        lastPingAt = nil
    }

    private func send(_ message: IucmMessage) {
        guard let conn = connection else { return }
        do {
            let data = try IucmCodec.encode(message)
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { log("send failed: \(error)") }
            })
        } catch {
            log("encode failed for \(message.type): \(error)")
        }
    }

    // MARK: - Message handling

    private func handle(_ message: IucmMessage) {
        switch message {
        case .start(let s):
            startStreaming(s)
        case .stop:
            log("STOP received")
            stopStreaming()
        case .ping(let ts):
            pingArmed = true
            lastPingAt = .now()
            send(.pong(ts))
        case .clientInfo(let c):
            // The simulator plays the phone: it only records who is on the other end
            // (PROTOCOL.md 4.11). Unknown kinds decode to .unknown, never an error.
            receiverInfo = c
            log("CLIENT_INFO kind=\(c.clientKind) name=\"\(c.name)\" version=\(c.version)")
        case .error(let e):
            log("receiver reported ERROR \(e.code): \(e.text)")
        default:
            log("ignoring unexpected \(message.type) from receiver")
        }
    }

    // MARK: - Streaming

    private func startStreaming(_ start: StartMessage) {
        stopStreaming()
        let width = Int(start.width), height = Int(start.height)
        let fps = max(1, Int(start.fps))
        log("START camera=\(start.cameraId) \(width)x\(height)@\(fps) \(start.bitrateKbps) kbps")

        guard start.cameraId == 0 else {
            send(.error(ErrorMessage(.formatUnsupported, "unknown camera id \(start.cameraId)")))
            return
        }
        do {
            renderer = try TestPatternRenderer(width: width, height: height)
            encoder = try HevcEncoder(width: width, height: height, fps: fps,
                                      bitrateKbps: Int(start.bitrateKbps))
        } catch {
            log("encoder setup failed: \(error)")
            send(.error(ErrorMessage(.encoderFailed, "\(error)")))
            renderer = nil; encoder = nil
            return
        }
        // Audio only when the receiver asked for it (START bit 0, PROTOCOL.md 4.2)
        // and the operator did not switch it off. A failing AAC encoder is not fatal:
        // the video path keeps running, the receiver just never sees AUDIO_CONFIG.
        if audioEnabled && start.wantsAudio {
            do {
                audioEncoder = try AacToneEncoder()
            } catch {
                log("audio encoder setup failed: \(error) — continuing without audio")
                audioEncoder = nil
            }
        }

        activeFormat = (start.width, start.height, UInt16(fps))
        sentHvcc = nil
        frameIndex = 0
        streamStart = .now()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(Int(1_000_000_000 / fps)), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        frameTimer = timer
    }

    private func stopStreaming() {
        frameTimer?.cancel(); frameTimer = nil
        encoder?.invalidate(); encoder = nil
        renderer = nil
        activeFormat = nil
        sentHvcc = nil
        audioEncoder = nil
        audioConfigSent = false
        audioFrameIndex = 0
    }

    private func tick() {
        guard let renderer, let encoder, let streamStart else { return }
        // pts comes off the steady uptime clock, so it never jumps with wall time.
        let ptsUs = (DispatchTime.now().uptimeNanoseconds - streamStart.uptimeNanoseconds) / 1000
        lastPtsUs = max(lastPtsUs + 1, ptsUs)
        let index = frameIndex
        frameIndex += 1
        do {
            let buffer = try renderer.render(frameIndex: index, ptsUs: lastPtsUs)
            try encoder.encode(buffer, ptsUs: lastPtsUs) { [weak self] frame in
                self?.queue.async { self?.emit(frame) }
            }
            pumpAudio(nowUs: ptsUs)
        } catch {
            log("frame \(index) failed: \(error)")
            send(.error(ErrorMessage(.encoderFailed, "\(error)")))
            stopStreaming()
        }
    }

    private func emit(_ frame: EncodedFrame) {
        guard connection != nil, let format = activeFormat else { return }

        // CONFIG goes out before the first frame and again whenever the encoder
        // hands us a different format description.
        if let hvcc = frame.hvcc, hvcc != sentHvcc {
            sentHvcc = hvcc
            send(.config(ConfigMessage(width: format.width, height: format.height,
                                       fps: format.fps, hvcc: hvcc)))
            log("CONFIG sent (hvcC \(hvcc.count) bytes)")
            sendAudioConfig()
        }
        guard sentHvcc != nil else { return }

        send(.video(VideoMessage(ptsUs: frame.ptsUs, isKeyframe: frame.isKeyframe, nalData: frame.nalData)))
        statFrames += 1
        statBytes += frame.nalData.count
        if frame.isKeyframe { statKeyframes += 1 }
        writeDump(frame)
    }

    // MARK: - Audio

    /// AUDIO_CONFIG must precede the first AUDIO (PROTOCOL.md 4.9); it goes out
    /// directly after CONFIG so the receiver has both cookies before any media.
    private func sendAudioConfig() {
        guard !audioConfigSent, let encoder = audioEncoder else { return }
        do {
            let asc = try encoder.magicCookie()
            send(.audioConfig(AudioConfigMessage(sampleRate: UInt32(encoder.sampleRate),
                                                 channels: UInt8(encoder.channels),
                                                 codec: .aacLC, asc: asc)))
            audioConfigSent = true
            log("AUDIO_CONFIG sent (asc \(asc.count) bytes, \(Int(encoder.sampleRate)) Hz)")
        } catch {
            log("audio cookie failed: \(error) — disabling audio")
            audioEncoder = nil
        }
    }

    /// Emits as many 1024-sample AAC frames as the elapsed stream time allows.
    /// pts is derived from the sample count, so it shares the VIDEO clock and
    /// stays exactly 48000/1024 frames per second on average.
    private func pumpAudio(nowUs: UInt64) {
        guard connection != nil, audioConfigSent, let encoder = audioEncoder else { return }
        let usPerFrame = Double(AacToneEncoder.samplesPerFrame) * 1_000_000 / encoder.sampleRate
        while Double(audioFrameIndex) * usPerFrame <= Double(nowUs) {
            let ptsUs = UInt64((Double(audioFrameIndex) * usPerFrame).rounded())
            do {
                let frame = try encoder.nextFrame()
                send(.audio(AudioMessage(ptsUs: ptsUs, frame: frame)))
                audioFrameIndex += 1
            } catch {
                log("audio encode failed: \(error) — disabling audio")
                audioEncoder = nil
                return
            }
        }
    }

    private func writeDump(_ frame: EncodedFrame) {
        guard let dumpHandle, let annexB = AnnexB.convert(lengthPrefixed: frame.nalData) else { return }
        var out = Data()
        if frame.isKeyframe, let hvcc = sentHvcc, let sets = AnnexB.parameterSets(fromHvcc: hvcc) {
            for set in sets { out.append(AnnexB.startCode); out.append(set) }
        }
        out.append(annexB)
        dumpHandle.write(out)
    }

    // MARK: - Status + watchdog

    private func startStatusTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1.0)
        timer.setEventHandler { [weak self] in self?.statusTick() }
        timer.resume()
        statusTimer = timer
    }

    private func statusTick() {
        if frameTimer != nil {
            let kbps = Double(statBytes) * 8.0 / 1000.0
            log(String(format: "fps=%d kbps=%.0f keyframes=%d", statFrames, kbps, statKeyframes))
        }
        statFrames = 0; statBytes = 0; statKeyframes = 0

        // The receiver pings every 2 s. The watchdog only arms after the first PING,
        // so a receiver that has not started pinging yet is not killed mid-handshake.
        if pingArmed, let last = lastPingAt {
            let idle = Double(DispatchTime.now().uptimeNanoseconds - last.uptimeNanoseconds) / 1e9
            if idle > Iucm.pingTimeout {
                log(String(format: "no PING for %.1f s — dropping receiver", idle))
                dropConnection(reason: "ping timeout")
            }
        }
    }
}

enum SimVersion {
    static let string = "0.1.0"
}
