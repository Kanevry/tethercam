import Foundation

/// Wire protocol "IUCM" (iPhone USB Cam Message), version 1.0.
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
    /// High byte major, low byte minor. Prototype = 1.0.
    public static let version: UInt16 = 0x0100
    public static let defaultPort: UInt16 = 7878
}

public enum IucmType: UInt8, Sendable, CaseIterable {
    case hello = 0x01
    case start = 0x02
    case stop = 0x03
    case config = 0x10
    case video = 0x11
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

public struct StartParams: Equatable, Sendable {
    public var cameraId: UInt8
    public var width: UInt16
    public var height: UInt16
    public var fps: UInt16
    public var bitrateKbps: UInt32
    public init(cameraId: UInt8, width: UInt16, height: UInt16, fps: UInt16, bitrateKbps: UInt32) {
        self.cameraId = cameraId
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrateKbps = bitrateKbps
    }
}

/// One decoded protocol message.
public enum IucmMessage: Equatable, Sendable {
    case hello(version: UInt16, deviceName: String, appVersion: String, cameras: [CameraDescriptor])
    case start(StartParams)
    case stop
    case config(width: UInt16, height: UInt16, fps: UInt16, hvcC: Data)
    /// `nalUnits` is the raw remainder after the pts field: a concatenation of
    /// 4-byte-big-endian-length-prefixed NAL units, passed through unchanged.
    case video(ptsUs: UInt64, keyframe: Bool, nalUnits: Data)
    case ping(timestampUs: UInt64)
    case pong(timestampUs: UInt64)
    case error(code: UInt16, text: String)

    public var type: IucmType {
        switch self {
        case .hello: return .hello
        case .start: return .start
        case .stop: return .stop
        case .config: return .config
        case .video: return .video
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
        case .stop:
            break
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
            msg = .start(StartParams(cameraId: try r.u8(), width: try r.u16(),
                                     height: try r.u16(), fps: try r.u16(),
                                     bitrateKbps: try r.u32()))
        case .stop:
            msg = .stop
        case .config:
            let w = try r.u16(), h = try r.u16(), fps = try r.u16()
            let len = Int(try r.u32())
            msg = .config(width: w, height: h, fps: fps, hvcC: try r.bytes(len))
        case .video:
            // Everything after pts is opaque: length-prefixed NAL units, passed through.
            msg = .video(ptsUs: try r.u64(), keyframe: flags & 0x01 != 0, nalUnits: r.rest())
        case .ping:
            msg = .ping(timestampUs: try r.u64())
        case .pong:
            msg = .pong(timestampUs: try r.u64())
        case .error:
            msg = .error(code: try r.u16(), text: try r.longString())
        }
        // VIDEO consumes the remainder by design; every other type is fixed-shape.
        if t != .video && !r.isAtEnd { throw IucmDecodeError.trailingBytes }
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
