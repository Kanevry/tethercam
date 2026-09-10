import Foundation

/// Wire protocol "IUCM" (iPhone USB Cam Message), version 1.2.
///
/// Framing: 12-byte header, little-endian:
///   magic  4  ASCII "IUCM"
///   type   1
///   flags  1  bit0 = keyframe (VIDEO only)
///   rsvd   2  = 0
///   length 4  payload length
///
/// All integers are little-endian EXCEPT the NAL length prefixes inside a
/// VIDEO payload, which are 4-byte big-endian (HVCC style, as VideoToolbox
/// emits them).
public enum Iucm {
    public static let magic: [UInt8] = Array("IUCM".utf8)
    public static let headerSize = 12
    /// Guard against absurd allocations from a corrupt stream (spec section 8).
    public static let maxPayload = 8 * 1024 * 1024
    /// High byte major, low byte minor. 1.1 added AUDIO_CONFIG/AUDIO (PROTOCOL.md 4.9/4.10),
    /// 1.2 added CLIENT_INFO (PROTOCOL.md 4.11). A 1.2 app still speaks to 1.0 and 1.1
    /// receivers: CLIENT_INFO is optional and its absence is not an error.
    public static let version: UInt16 = 0x0102
    public static let defaultPort: UInt16 = 7878
}

public enum IucmType: UInt8, Sendable, CaseIterable {
    case hello = 0x01
    case start = 0x02
    case stop = 0x03
    /// CLIENT_INFO, Mac to app, optional (PROTOCOL.md 4.11, since 1.2).
    case clientInfo = 0x04
    case stats = 0x12
    case config = 0x10
    case video = 0x11
    case audioConfig = 0x13
    case audio = 0x14
    case ping = 0x20
    case pong = 0x21
    case error = 0x30
}

public enum IucmErrorCode: UInt16, Sendable, CaseIterable {
    case busy = 1
    case cameraDenied = 2
    case formatUnsupported = 3
    case encoderFailed = 4
    case versionUnsupported = 5
    /// Microphone permission denied. Not fatal: video keeps running without audio.
    case micDenied = 6
}

/// AUDIO_CONFIG `codec` field. See `protocol/PROTOCOL.md` section 4.9.
public enum IucmAudioCodec: UInt8, Sendable, CaseIterable {
    case aacLC = 1
}

/// CLIENT_INFO `kind` field. See `protocol/PROTOCOL.md` section 4.11.
public enum IucmClientKind: UInt8, Sendable, CaseIterable {
    case unknown = 0
    case obsPlugin = 1
    case macApp = 2
    case tool = 3
}

/// Who is connected, as announced in CLIENT_INFO (PROTOCOL.md 4.11).
///
/// `name` and `version` arrive in English and are shown verbatim; only the
/// surrounding sentence is localised, never the wire string. `nil` receiver info
/// means a 1.0/1.1 receiver that never identified itself.
public struct ReceiverInfo: Equatable, Sendable {
    /// Raw wire value. Unknown values map to `.unknown` in `clientKind` (4.11).
    public var kind: UInt8
    public var name: String
    public var version: String

    public init(kind: UInt8, name: String, version: String) {
        self.kind = kind
        self.name = name
        self.version = version
    }

    public init(kind: IucmClientKind, name: String, version: String) {
        self.init(kind: kind.rawValue, name: name, version: version)
    }

    public var clientKind: IucmClientKind { IucmClientKind(rawValue: kind) ?? .unknown }
}

public enum CameraPosition: UInt8, Sendable {
    case back = 0
    case front = 1
}

public struct CameraDescriptor: Equatable, Sendable {
    public var id: UInt8
    public var position: CameraPosition
    public var name: String
    public init(id: UInt8, position: CameraPosition, name: String) {
        self.id = id
        self.position = position
        self.name = name
    }
}

/// STATS (`0x12`) payload — device-side orientation and leveller state, once per
/// second while a receiver is connected. See `protocol/PROTOCOL.md` section 4.8.
///
/// Fields are stored exactly as they travel: fixed-point integers, so a decoded
/// message compares byte-identical to the encoded one. The `init(continuousDeg:…)`
/// overload does the scaling and saturation.
public struct DeviceStats: Equatable, Sendable {
    /// Bit 0 — auto rotation is on (gravity drives the sector).
    public static let flagAutoRotation: UInt8 = 1 << 0
    /// Bit 1 — horizon levelling is on.
    public static let flagHorizonLeveling: UInt8 = 1 << 1
    /// Bit 2 — the camera runs above the output size so the fill zoom crops out of
    /// surplus pixels instead of upscaling.
    public static let flagOversampling: UInt8 = 1 << 2
    /// Bit 3 — in-plane gravity is below the flat threshold, angle is being held.
    public static let flagFlatHold: UInt8 = 1 << 3
    /// Bit 4 — audio is currently being sent (reserved in 1.1, no sender logic yet).
    public static let flagAudioActive: UInt8 = 1 << 4
    /// Bit 5 — the user muted the microphone (reserved in 1.1, no sender logic yet).
    public static let flagAudioMuted: UInt8 = 1 << 5

    public var continuousAngleX10: Int16
    public var sector: UInt16
    public var residualX10: Int16
    public var gravityMX1000: UInt16
    public var levelerMsX10: UInt16
    public var droppedFrames: UInt16
    public var sourceWidth: UInt16
    public var sourceHeight: UInt16
    public var outputWidth: UInt16
    public var outputHeight: UInt16
    public var flags: UInt8
    public var cameraId: UInt8

    public init(continuousAngleX10: Int16, sector: UInt16, residualX10: Int16,
                gravityMX1000: UInt16, levelerMsX10: UInt16, droppedFrames: UInt16,
                sourceWidth: UInt16, sourceHeight: UInt16,
                outputWidth: UInt16, outputHeight: UInt16,
                flags: UInt8, cameraId: UInt8) {
        self.continuousAngleX10 = continuousAngleX10
        self.sector = sector
        self.residualX10 = residualX10
        self.gravityMX1000 = gravityMX1000
        self.levelerMsX10 = levelerMsX10
        self.droppedFrames = droppedFrames
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
        self.flags = flags
        self.cameraId = cameraId
    }

    /// Saturating conversion from the physical values. Everything is clamped
    /// rather than trapped: telemetry must never crash the streaming app.
    public init(continuousDeg: Double, sector: Double, residualDeg: Double,
                gravityM: Double, levelerMs: Double, droppedFrames: Int,
                sourceWidth: Int, sourceHeight: Int, outputWidth: Int, outputHeight: Int,
                flags: UInt8, cameraId: UInt8) {
        func i16(_ v: Double) -> Int16 { Int16(max(-32768, min(32767, v.rounded()))) }
        func u16(_ v: Double) -> UInt16 { UInt16(max(0, min(65535, v.rounded()))) }
        self.init(continuousAngleX10: i16(continuousDeg * 10),
                  sector: u16(sector),
                  residualX10: i16(residualDeg * 10),
                  gravityMX1000: u16(gravityM * 1000),
                  levelerMsX10: u16(levelerMs * 10),
                  droppedFrames: u16(Double(droppedFrames)),
                  sourceWidth: u16(Double(sourceWidth)),
                  sourceHeight: u16(Double(sourceHeight)),
                  outputWidth: u16(Double(outputWidth)),
                  outputHeight: u16(Double(outputHeight)),
                  flags: flags, cameraId: cameraId)
    }

    public var continuousDeg: Double { Double(continuousAngleX10) / 10 }
    public var residualDeg: Double { Double(residualX10) / 10 }
    public var gravityM: Double { Double(gravityMX1000) / 1000 }
    public var levelerMs: Double { Double(levelerMsX10) / 10 }
}

/// START (`0x02`) payload. See `protocol/PROTOCOL.md` section 4.2.
///
/// `flags` is the byte added in protocol 1.1. A 1.0 receiver sends an 11-byte
/// START without it; that decodes as `flags == 0`, i.e. "no audio wanted".
public struct StartParams: Equatable, Sendable {
    /// Bit 0 — the receiver wants audio (AUDIO_CONFIG + AUDIO).
    public static let flagAudio: UInt8 = 1 << 0

    public var cameraId: UInt8
    public var width: UInt16
    public var height: UInt16
    public var fps: UInt16
    public var bitrateKbps: UInt32
    public var flags: UInt8

    public init(cameraId: UInt8, width: UInt16, height: UInt16, fps: UInt16,
                bitrateKbps: UInt32, flags: UInt8 = 0) {
        self.cameraId = cameraId
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrateKbps = bitrateKbps
        self.flags = flags
    }

    /// Convenience view of `flags` bit 0.
    public var wantsAudio: Bool {
        get { flags & StartParams.flagAudio != 0 }
        set {
            if newValue { flags |= StartParams.flagAudio }
            else { flags &= ~StartParams.flagAudio }
        }
    }
}

/// One decoded protocol message.
public enum IucmMessage: Equatable, Sendable {
    case hello(version: UInt16, deviceName: String, appVersion: String, cameras: [CameraDescriptor])
    case start(StartParams)
    case stop
    /// CLIENT_INFO (`0x04`): who the receiver is (PROTOCOL.md 4.11).
    case clientInfo(ReceiverInfo)
    case stats(DeviceStats)
    case config(width: UInt16, height: UInt16, fps: UInt16, hvcC: Data)
    /// `nalUnits` is the raw remainder after the pts field: a concatenation of
    /// 4-byte-big-endian-length-prefixed NAL units, passed through unchanged.
    case video(ptsUs: UInt64, keyframe: Bool, nalUnits: Data)
    /// AUDIO_CONFIG (`0x13`): `asc` is the AudioSpecificConfig magic cookie from
    /// the encoder, passed through unchanged. `codec` uses `IucmAudioCodec`.
    case audioConfig(sampleRate: UInt32, channels: UInt8, codec: UInt8, asc: Data)
    /// AUDIO (`0x14`): exactly one raw AAC access unit (1024 samples, no ADTS header).
    case audio(ptsUs: UInt64, frame: Data)
    case ping(timestampUs: UInt64)
    case pong(timestampUs: UInt64)
    case error(code: UInt16, text: String)

    public var type: IucmType {
        switch self {
        case .hello: return .hello
        case .start: return .start
        case .stop: return .stop
        case .clientInfo: return .clientInfo
        case .stats: return .stats
        case .config: return .config
        case .video: return .video
        case .audioConfig: return .audioConfig
        case .audio: return .audio
        case .ping: return .ping
        case .pong: return .pong
        case .error: return .error
        }
    }
}

public enum IucmDecodeError: Error, Equatable {
    case badMagic
    case unknownType(UInt8)
    case truncatedPayload
    case trailingBytes
    case invalidUTF8
    case payloadTooLarge(UInt32)
}

// MARK: - Little-endian byte helpers

/// Append-only LE writer. Kept tiny and allocation-friendly for the video path.
struct ByteWriter {
    private(set) var data = Data()
    init(reserving n: Int = 0) { data.reserveCapacity(n) }
    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func u16(_ v: UInt16) { data.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)]) }
    mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    mutating func u32(_ v: UInt32) {
        data.append(contentsOf: (0..<4).map { UInt8((v >> (8 * UInt32($0))) & 0xFF) })
    }
    mutating func u64(_ v: UInt64) {
        data.append(contentsOf: (0..<8).map { UInt8((v >> (8 * UInt64($0))) & 0xFF) })
    }
    mutating func bytes(_ d: Data) { data.append(d) }
    /// u8 length prefix + UTF-8. Truncates at 255 bytes on a UTF-8 boundary.
    mutating func shortString(_ s: String) {
        var utf8 = Array(s.utf8)
        if utf8.count > 255 {
            utf8 = Array(String(decoding: utf8.prefix(255), as: UTF8.self).utf8)
            if utf8.count > 255 { utf8 = Array(utf8.prefix(255)) }
        }
        u8(UInt8(utf8.count))
        data.append(contentsOf: utf8)
    }
    /// u16 length prefix + UTF-8.
    mutating func longString(_ s: String) {
        let utf8 = Array(s.utf8.prefix(65535))
        u16(UInt16(utf8.count))
        data.append(contentsOf: utf8)
    }
}

/// Bounds-checked LE reader over a payload slice.
struct ByteReader {
    private let buf: [UInt8]
    private var i = 0
    init(_ d: Data) { buf = [UInt8](d) }
    var remaining: Int { buf.count - i }
    var isAtEnd: Bool { remaining == 0 }

    mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw IucmDecodeError.truncatedPayload }
        defer { i += 1 }
        return buf[i]
    }
    mutating func u16() throws -> UInt16 {
        guard remaining >= 2 else { throw IucmDecodeError.truncatedPayload }
        defer { i += 2 }
        return UInt16(buf[i]) | UInt16(buf[i + 1]) << 8
    }
    mutating func u32() throws -> UInt32 {
        guard remaining >= 4 else { throw IucmDecodeError.truncatedPayload }
        defer { i += 4 }
        var v: UInt32 = 0
        for k in 0..<4 { v |= UInt32(buf[i + k]) << (8 * UInt32(k)) }
        return v
    }
    mutating func u64() throws -> UInt64 {
        guard remaining >= 8 else { throw IucmDecodeError.truncatedPayload }
        defer { i += 8 }
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(buf[i + k]) << (8 * UInt64(k)) }
        return v
    }
    mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }
    mutating func bytes(_ n: Int) throws -> Data {
        guard n >= 0, remaining >= n else { throw IucmDecodeError.truncatedPayload }
        defer { i += n }
        return Data(buf[i..<(i + n)])
    }
    mutating func rest() -> Data {
        defer { i = buf.count }
        return Data(buf[i...])
    }
    mutating func shortString() throws -> String {
        let n = Int(try u8())
        return try string(n)
    }
    mutating func longString() throws -> String {
        let n = Int(try u16())
        return try string(n)
    }
    private mutating func string(_ n: Int) throws -> String {
        let d = try bytes(n)
        guard let s = String(data: d, encoding: .utf8) else { throw IucmDecodeError.invalidUTF8 }
        return s
    }
}

// MARK: - Codec

public enum IucmCodec {
    /// Frames a message into header + payload, ready for the socket.
    public static func encode(_ m: IucmMessage) -> Data {
        var p = ByteWriter(reserving: 256)
        var flags: UInt8 = 0

        switch m {
        case let .hello(version, deviceName, appVersion, cameras):
            p.u16(version)
            p.shortString(deviceName)
            p.shortString(appVersion)
            p.u8(UInt8(min(cameras.count, 255)))
            for c in cameras.prefix(255) {
                p.u8(c.id)
                p.u8(c.position.rawValue)
                p.shortString(c.name)
            }
        case let .start(s):
            p.u8(s.cameraId)
            p.u16(s.width)
            p.u16(s.height)
            p.u16(s.fps)
            p.u32(s.bitrateKbps)
            // Short form (11 byte) when there is nothing to say, so a 1.0 app that
            // rejects trailing bytes still understands a 1.1 receiver.
            if s.flags != 0 { p.u8(s.flags) }
        case .stop:
            break
        case let .clientInfo(info):
            p.u8(info.kind)
            p.shortString(info.name)
            p.shortString(info.version)
        case let .stats(st):
            p.i16(st.continuousAngleX10)
            p.u16(st.sector)
            p.i16(st.residualX10)
            p.u16(st.gravityMX1000)
            p.u16(st.levelerMsX10)
            p.u16(st.droppedFrames)
            p.u16(st.sourceWidth)
            p.u16(st.sourceHeight)
            p.u16(st.outputWidth)
            p.u16(st.outputHeight)
            p.u8(st.flags)
            p.u8(st.cameraId)
        case let .config(w, h, fps, hvcC):
            p.u16(w)
            p.u16(h)
            p.u16(fps)
            p.u32(UInt32(hvcC.count))
            p.bytes(hvcC)
        case let .video(pts, keyframe, nal):
            p.u64(pts)
            p.bytes(nal)
            if keyframe { flags |= 0x01 }
        case let .audioConfig(sampleRate, channels, codec, asc):
            p.u32(sampleRate)
            p.u8(channels)
            p.u8(codec)
            p.u16(UInt16(min(asc.count, 0xFFFF)))
            p.bytes(asc.prefix(0xFFFF))
        case let .audio(pts, frame):
            p.u64(pts)
            p.bytes(frame)
        case let .ping(ts), let .pong(ts):
            p.u64(ts)
        case let .error(code, text):
            p.u16(code)
            p.longString(text)
        }

        let payload = p.data
        var out = ByteWriter(reserving: Iucm.headerSize + payload.count)
        out.bytes(Data(Iucm.magic))
        out.u8(m.type.rawValue)
        out.u8(flags)
        out.u16(0)
        out.u32(UInt32(payload.count))
        out.bytes(payload)
        return out.data
    }

    /// Decodes a payload that the framer already validated and sized.
    public static func decodePayload(type: UInt8, flags: UInt8, payload: Data) throws -> IucmMessage {
        guard let t = IucmType(rawValue: type) else { throw IucmDecodeError.unknownType(type) }
        var r = ByteReader(payload)
        let msg: IucmMessage
        switch t {
        case .hello:
            let version = try r.u16()
            let device = try r.shortString()
            let app = try r.shortString()
            let count = Int(try r.u8())
            var cams: [CameraDescriptor] = []
            cams.reserveCapacity(count)
            for _ in 0..<count {
                let id = try r.u8()
                let pos = CameraPosition(rawValue: try r.u8()) ?? .back
                cams.append(CameraDescriptor(id: id, position: pos, name: try r.shortString()))
            }
            msg = .hello(version: version, deviceName: device, appVersion: app, cameras: cams)
        case .start:
            var s = StartParams(cameraId: try r.u8(), width: try r.u16(),
                                height: try r.u16(), fps: try r.u16(),
                                bitrateKbps: try r.u32())
            // Protocol 1.1 appends a flags byte; 1.0 senders stop after 11 byte.
            // Anything beyond that belongs to a later minor version: ignore it (4.2).
            if !r.isAtEnd {
                s.flags = try r.u8()
                _ = r.rest()
            }
            msg = .start(s)
        case .stop:
            msg = .stop
        case .clientInfo:
            let kind = try r.u8()
            let name = try r.shortString()
            let version = try r.shortString()
            // Trailing bytes belong to a later minor version: ignore them (4.11).
            _ = r.rest()
            msg = .clientInfo(ReceiverInfo(kind: kind, name: name, version: version))
        case .stats:
            msg = .stats(DeviceStats(continuousAngleX10: try r.i16(), sector: try r.u16(),
                                     residualX10: try r.i16(), gravityMX1000: try r.u16(),
                                     levelerMsX10: try r.u16(), droppedFrames: try r.u16(),
                                     sourceWidth: try r.u16(), sourceHeight: try r.u16(),
                                     outputWidth: try r.u16(), outputHeight: try r.u16(),
                                     flags: try r.u8(), cameraId: try r.u8()))
        case .config:
            let w = try r.u16(), h = try r.u16(), fps = try r.u16()
            let len = Int(try r.u32())
            msg = .config(width: w, height: h, fps: fps, hvcC: try r.bytes(len))
        case .video:
            // Everything after pts is opaque: length-prefixed NAL units, passed through.
            msg = .video(ptsUs: try r.u64(), keyframe: flags & 0x01 != 0, nalUnits: r.rest())
        case .audioConfig:
            let rate = try r.u32(), channels = try r.u8(), codec = try r.u8()
            let ascLen = Int(try r.u16())
            msg = .audioConfig(sampleRate: rate, channels: channels, codec: codec,
                               asc: try r.bytes(ascLen))
        case .audio:
            // Everything after pts is one raw AAC access unit, passed through.
            msg = .audio(ptsUs: try r.u64(), frame: r.rest())
        case .ping:
            msg = .ping(timestampUs: try r.u64())
        case .pong:
            msg = .pong(timestampUs: try r.u64())
        case .error:
            msg = .error(code: try r.u16(), text: try r.longString())
        }
        // VIDEO, AUDIO and CLIENT_INFO consume the remainder by design; every other
        // type is fixed-shape. START is length-tolerant and already consumed its
        // optional byte.
        if t != .video && t != .audio && t != .clientInfo && !r.isAtEnd {
            throw IucmDecodeError.trailingBytes
        }
        return msg
    }

    /// Convenience for tests: decode one complete framed message.
    public static func decodeFrame(_ frame: Data) throws -> IucmMessage {
        let b = [UInt8](frame)
        guard b.count >= Iucm.headerSize else { throw IucmDecodeError.truncatedPayload }
        guard Array(b[0..<4]) == Iucm.magic else { throw IucmDecodeError.badMagic }
        var len: UInt32 = 0
        for k in 0..<4 { len |= UInt32(b[8 + k]) << (8 * UInt32(k)) }
        guard b.count >= Iucm.headerSize + Int(len) else { throw IucmDecodeError.truncatedPayload }
        return try decodePayload(type: b[4], flags: b[5],
                                 payload: Data(b[Iucm.headerSize..<(Iucm.headerSize + Int(len))]))
    }
}

// MARK: - NAL helpers

public enum HvccNal {
    /// Splits a VideoToolbox-style HVCC buffer into its NAL units.
    /// Length prefixes are 4-byte BIG-endian. Returns nil on malformed input.
    public static func split(_ data: Data) -> [Data]? {
        let b = [UInt8](data)
        var out: [Data] = []
        var i = 0
        while i + 4 <= b.count {
            let n = Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
            i += 4
            guard n >= 0, i + n <= b.count else { return nil }
            out.append(Data(b[i..<(i + n)]))
            i += n
        }
        return i == b.count ? out : nil
    }

    /// Joins NAL units with 4-byte big-endian length prefixes.
    public static func join(_ nals: [Data]) -> Data {
        var out = Data()
        for n in nals {
            let c = UInt32(n.count)
            out.append(contentsOf: [UInt8(c >> 24 & 0xFF), UInt8(c >> 16 & 0xFF),
                                    UInt8(c >> 8 & 0xFF), UInt8(c & 0xFF)])
            out.append(n)
        }
        return out
    }
}
