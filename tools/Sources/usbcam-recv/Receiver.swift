import Foundation
import IucmProtocol
#if canImport(Darwin)
import Darwin
#endif

enum RecvError: Error, CustomStringConvertible {
    case protocolViolation(String)
    case timeout(String)
    case remote(String)
    case io(String)

    var description: String {
        switch self {
        case .protocolViolation(let m): return "protocol error: \(m)"
        case .timeout(let m): return "timeout: \(m)"
        case .remote(let m): return "remote error: \(m)"
        case .io(let m): return "io error: \(m)"
        }
    }
}

func logLine(_ s: String) {
    FileHandle.standardError.write(Data("\(s)\n".utf8))
}

private func nowUs() -> UInt64 { DispatchTime.now().uptimeNanoseconds / 1000 }

struct Summary: Encodable {
    var frames: Int
    var fps_avg: Double
    var kbps_avg: Double
    var keyframes: Int
    var ping_rtt_ms_avg: Double
    var first_frame_ms: Double
    var nals: Int
    var width: Int
    var height: Int
    var audio_frames: Int
    var audio_decoded_samples: Int
    var audio_sample_rate: Int
    /// Wall time from START to the first AUDIO, in ms; 0 when no audio arrived.
    var audio_first_frame_ms: Double
    /// First AUDIO pts minus first VIDEO pts, in ms — the A/V alignment at stream start.
    var audio_video_pts_skew_ms: Double
}

final class Receiver {
    private let fd: Int32
    private let opts: Options
    private var parser = IucmFrameParser()
    private var writer: AnnexBWriter?
    private var audioDumpHandle: FileHandle?

    // Statistik
    private var frames = 0, keyframes = 0, nals = 0, videoBytes = 0
    private var firstPts: UInt64?, lastPts: UInt64?
    private var configSeen = false
    private var configWH = (0, 0)
    private var rttSamplesUs: [UInt64] = []
    private var pendingPings: [UInt64: UInt64] = [:]
    private var missedPongs = 0
    private var firstFrameMs: Double = 0
    private var startSentUs: UInt64 = 0

    // Intervall-Statistik fuer die Sekundenzeile
    // Audio (PROTOCOL.md 4.9/4.10)
    private var audioConfig: AudioConfigMessage?
    private var audioDecoder: AacDecoder?
    private var audioFrames = 0
    private var audioSamples = 0
    private var firstAudioPts: UInt64?
    private var audioFirstFrameMs: Double = 0

    private var winFrames = 0, winBytes = 0, winNals = 0
    private var lastTickUs: UInt64 = 0
    private var lastPingUs: UInt64 = 0
    private var lastRttMs: Double = -1

    init(fd: Int32, opts: Options) throws {
        self.fd = fd
        self.opts = opts
        if let p = opts.dumpPath { self.writer = try AnnexBWriter(path: p) }
        if let p = opts.audioDumpPath {
            guard FileManager.default.createFile(atPath: p, contents: nil),
                  let h = FileHandle(forWritingAtPath: p) else {
                throw RecvError.io("cannot open audio dump file \(p)")
            }
            self.audioDumpHandle = h
        }
    }

    deinit {
        writer?.close()
        try? audioDumpHandle?.close()
    }

    // MARK: - Socket

    private func sendAll(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: off), raw.count - off)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw RecvError.io("write: \(String(cString: strerror(errno)))")
                }
                if n == 0 { throw RecvError.io("write returned 0") }
                off += n
            }
        }
    }

    private func send(_ msg: IucmMessage) throws { try sendAll(try IucmCodec.encode(msg)) }

    /// Wartet bis zu `timeoutMs` auf Daten und schiebt sie in den Parser.
    /// Liefert die dabei fertig gewordenen Nachrichten (moeglicherweise leer).
    private func pump(timeoutMs: Int32) throws -> [IucmMessage] {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let rc = poll(&pfd, 1, timeoutMs)
        if rc < 0 {
            if errno == EINTR { return [] }
            throw RecvError.io("poll: \(String(cString: strerror(errno)))")
        }
        if rc == 0 { return [] }
        var buf = [UInt8](repeating: 0, count: 1 << 16)
        let n = read(fd, &buf, buf.count)
        if n < 0 {
            if errno == EINTR || errno == EAGAIN { return [] }
            throw RecvError.io("read: \(String(cString: strerror(errno)))")
        }
        if n == 0 { throw RecvError.io("connection closed by sender") }
        do {
            return try parser.append(Data(buf[0..<n]))
        } catch {
            throw RecvError.protocolViolation("\(error)")
        }
    }

    // MARK: - Ablauf

    func run() throws -> Summary {
        let hello = try awaitHello()
        guard hello.version >> 8 == 1 else {
            throw RecvError.protocolViolation(
                "unsupported major version \(hello.version >> 8) (0x\(String(format: "%04x", hello.version)))")
        }
        let cams = hello.cameras.map { "\($0.id)=\($0.name)/\($0.position)" }.joined(separator: ", ")
        logLine("HELLO   version=0x\(String(format: "%04x", hello.version)) device=\"\(hello.deviceName)\" "
                + "app=\(hello.appVersion) cameras=[\(cams)]")

        let start = StartMessage(cameraId: opts.camera, width: opts.width, height: opts.height,
                                 fps: opts.fps, bitrateKbps: opts.bitrate,
                                 flags: opts.audio ? StartMessage.flagAudio : 0)
        try send(.start(start))
        startSentUs = nowUs()
        lastTickUs = startSentUs
        lastPingUs = startSentUs
        logLine("START   camera=\(opts.camera) \(opts.width)x\(opts.height)@\(opts.fps) \(opts.bitrate) kbps "
                + "audio=\(opts.audio ? "on" : "off")")

        try stream()
        return summary()
    }

    private func awaitHello() throws -> HelloMessage {
        let deadline = nowUs() + UInt64(opts.helloTimeout * 1e6)
        var queue: [IucmMessage] = []
        while nowUs() < deadline {
            queue = try pump(timeoutMs: 200)
            for msg in queue {
                switch msg {
                case .hello(let h): return h
                case .error(let e): throw RecvError.remote("ERROR \(e.code): \(e.text)")
                default: throw RecvError.protocolViolation("expected HELLO, got \(msg.type)")
                }
            }
        }
        throw RecvError.timeout("no HELLO within \(opts.helloTimeout) s — is the camera app listening?")
    }

    private func stream() throws {
        var deadline: UInt64?
        var lastDataUs = nowUs()

        while true {
            let msgs = try pump(timeoutMs: 100)
            if !msgs.isEmpty { lastDataUs = nowUs() }
            for msg in msgs {
                switch msg {
                case .config(let c):
                    configSeen = true
                    configWH = (Int(c.width), Int(c.height))
                    logLine("CONFIG  \(c.width)x\(c.height)@\(c.fps) hvcc_len=\(c.hvcc.count)")
                    try writer?.setParameterSets(hvcc: c.hvcc)
                    if deadline == nil, let s = opts.seconds { deadline = nowUs() + UInt64(s * 1e6) }
                case .video(let v):
                    try handleVideo(v)
                case .pong(let ts):
                    if let sent = pendingPings.removeValue(forKey: ts) {
                        let rtt = nowUs() &- sent
                        rttSamplesUs.append(rtt)
                        lastRttMs = Double(rtt) / 1000.0
                    } else {
                        throw RecvError.protocolViolation("PONG echo \(ts) was never sent as PING")
                    }
                case .error(let e):
                    throw RecvError.remote("ERROR \(e.code): \(e.text)")
                case .stats(let st):
                    // 0x12, PROTOCOL.md 4.8 — device telemetry, informational only.
                    logLine(String(format: "STATS   angle=%+.1f sector=%u residual=%+.1f m=%.2f "
                                   + "leveler=%.1fms drop=%u src=%ux%u out=%ux%u flags=0x%02x cam=%u",
                                   st.continuousDeg, st.sector, st.residualDeg, st.gravityM,
                                   st.levelerMs, st.droppedFrames, st.sourceWidth, st.sourceHeight,
                                   st.outputWidth, st.outputHeight, st.flags, st.cameraId))
                case .hello:
                    throw RecvError.protocolViolation("second HELLO during streaming")
                case .audioConfig(let a):
                    try handleAudioConfig(a)
                case .audio(let a):
                    try handleAudio(a)
                case .start, .stop, .ping:
                    throw RecvError.protocolViolation("unexpected \(msg.type) from sender")
                }
            }

            let t = nowUs()
            if t &- lastPingUs >= 2_000_000 {
                lastPingUs = t
                let stamp = t
                pendingPings[stamp] = t
                try send(.ping(stamp))
                pendingPings = pendingPings.filter { t &- $0.value < 8_000_000 }
                missedPongs = pendingPings.count
                if missedPongs >= 3 {
                    throw RecvError.timeout("3 missing PONG (~6 s) — link is dead")
                }
            }
            if t &- lastTickUs >= 1_000_000 {
                let dt = Double(t &- lastTickUs) / 1e6
                logLine(String(format: "STAT    %.1f fps  %.0f kbps  keyframes=%d  nals=%d  rtt=%@",
                               Double(winFrames) / dt, Double(winBytes) * 8 / 1000 / dt,
                               keyframes, winNals,
                               lastRttMs < 0 ? "-" : String(format: "%.1f ms", lastRttMs)))
                winFrames = 0; winBytes = 0; winNals = 0
                lastTickUs = t
            }
            if t &- lastDataUs > 6_000_000 {
                throw RecvError.timeout("no message for 6 s")
            }
            if let d = deadline, t >= d {
                try send(.stop)
                logLine("STOP    sent")
                return
            }
        }
    }

    // MARK: - Audio

    private func handleAudioConfig(_ c: AudioConfigMessage) throws {
        guard audioConfig == nil else {
            throw RecvError.protocolViolation("second AUDIO_CONFIG during streaming")
        }
        guard c.codec == IucmAudioCodec.aacLC.rawValue else {
            throw RecvError.protocolViolation("unsupported audio codec \(c.codec) (only 1 = AAC-LC)")
        }
        audioConfig = c
        logLine("AUDIOCFG \(c.sampleRate) Hz ch=\(c.channels) codec=\(c.codec) asc_len=\(c.asc.count)")
        do {
            audioDecoder = try AacDecoder(sampleRate: Double(c.sampleRate),
                                          channels: UInt32(max(1, c.channels)), asc: c.asc)
        } catch {
            throw RecvError.protocolViolation("audio decoder setup failed: \(error)")
        }
    }

    private func handleAudio(_ a: AudioMessage) throws {
        guard let config = audioConfig else {
            throw RecvError.protocolViolation("AUDIO before AUDIO_CONFIG")
        }
        if firstAudioPts == nil {
            firstAudioPts = a.ptsUs
            audioFirstFrameMs = Double(nowUs() &- startSentUs) / 1000.0
        }
        audioFrames += 1
        if let decoder = audioDecoder {
            audioSamples += try decoder.decode(frame: a.frame)
        }
        if let h = audioDumpHandle {
            guard let header = Adts.header(payloadLength: a.frame.count,
                                           sampleRate: Int(config.sampleRate),
                                           channels: Int(config.channels)) else {
                throw RecvError.protocolViolation(
                    "cannot frame AUDIO as ADTS (\(config.sampleRate) Hz, \(config.channels) ch, "
                    + "\(a.frame.count) bytes)")
            }
            h.write(header)
            h.write(a.frame)
        }
    }

    private func handleVideo(_ v: VideoMessage) throws {
        guard configSeen else { throw RecvError.protocolViolation("VIDEO before CONFIG") }
        if let last = lastPts, v.ptsUs <= last {
            throw RecvError.protocolViolation("pts not monotonic: \(v.ptsUs) after \(last)")
        }
        var n = 0
        if let w = writer {
            n = try w.write(nalData: v.nalData, isKeyframe: v.isKeyframe)
        } else {
            guard let c = countNals(v.nalData) else {
                throw RecvError.protocolViolation("VIDEO payload is not 4-byte-BE length prefixed")
            }
            n = c
        }
        if firstPts == nil {
            firstPts = v.ptsUs
            firstFrameMs = Double(nowUs() &- startSentUs) / 1000.0
        }
        lastPts = v.ptsUs
        frames += 1
        nals += n
        videoBytes += v.nalData.count
        winFrames += 1
        winBytes += v.nalData.count
        winNals += n
        if v.isKeyframe { keyframes += 1 }
    }

    /// Laeuft die 4-Byte-BE-Praefixe ab; nil bei Rahmenfehler (PROTOCOL.md 4.6).
    private func countNals(_ data: Data) -> Int? {
        let b = [UInt8](data)
        var off = 0, count = 0
        while off + 4 <= b.count {
            var len = 0
            for i in 0..<4 { len = (len << 8) | Int(b[off + i]) }
            off += 4 + len
            count += 1
            if off > b.count { return nil }
        }
        return off == b.count ? count : nil
    }

    private func summary() -> Summary {
        let span = (frames > 1 && firstPts != nil && lastPts != nil)
            ? Double(lastPts! - firstPts!) / 1e6 : 0
        let skew: Double = (firstAudioPts != nil && firstPts != nil)
            ? (Double(firstAudioPts!) - Double(firstPts!)) / 1000.0 : 0
        let rttAvg = rttSamplesUs.isEmpty ? -1
            : Double(rttSamplesUs.reduce(0, +)) / Double(rttSamplesUs.count) / 1000.0
        return Summary(frames: frames,
                       fps_avg: span > 0 ? Double(frames - 1) / span : 0,
                       kbps_avg: span > 0 ? Double(videoBytes) * 8 / 1000 / span : 0,
                       keyframes: keyframes,
                       ping_rtt_ms_avg: rttAvg,
                       first_frame_ms: firstFrameMs,
                       nals: nals,
                       width: configWH.0, height: configWH.1,
                       audio_frames: audioFrames,
                       audio_decoded_samples: audioSamples,
                       audio_sample_rate: Int(audioConfig?.sampleRate ?? 0),
                       audio_first_frame_ms: audioFirstFrameMs,
                       audio_video_pts_skew_ms: skew)
    }
}
