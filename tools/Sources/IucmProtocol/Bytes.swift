import Foundation

/// Little-endian byte writer for protocol payloads.
struct ByteWriter {
    private(set) var bytes: [UInt8] = []

    mutating func u8(_ v: UInt8) { bytes.append(v) }

    mutating func u16(_ v: UInt16) {
        bytes.append(UInt8(v & 0xFF))
        bytes.append(UInt8((v >> 8) & 0xFF))
    }

    mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }

    mutating func u32(_ v: UInt32) {
        for i in 0..<4 { bytes.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) }
    }

    mutating func u64(_ v: UInt64) {
        for i in 0..<8 { bytes.append(UInt8((v >> (8 * UInt64(i))) & 0xFF)) }
    }

    mutating func raw<C: Collection>(_ v: C) where C.Element == UInt8 {
        bytes.append(contentsOf: v)
    }

    /// u8 length prefix + UTF-8 bytes.
    mutating func string8(_ s: String) throws {
        let utf8 = Array(s.utf8)
        guard utf8.count <= 255 else { throw IucmProtocolError.stringTooLong(utf8.count) }
        u8(UInt8(utf8.count))
        raw(utf8)
    }

    /// u16 length prefix + UTF-8 bytes.
    mutating func string16(_ s: String) throws {
        let utf8 = Array(s.utf8)
        guard utf8.count <= 0xFFFF else { throw IucmProtocolError.stringTooLong(utf8.count) }
        u16(UInt16(utf8.count))
        raw(utf8)
    }
}

/// Little-endian byte reader over a payload slice. Throws on short reads.
struct ByteReader {
    private let bytes: [UInt8]
    private var offset: Int
    private let messageType: UInt8

    init(_ bytes: [UInt8], type: UInt8) {
        self.bytes = bytes
        self.offset = 0
        self.messageType = type
    }

    var remaining: Int { bytes.count - offset }
    var isAtEnd: Bool { remaining == 0 }

    private mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard remaining >= n else { throw IucmProtocolError.truncatedPayload(type: messageType) }
        let slice = bytes[offset..<(offset + n)]
        offset += n
        return slice
    }

    mutating func u8() throws -> UInt8 { try take(1).first! }

    mutating func u16() throws -> UInt16 {
        let s = Array(try take(2))
        return UInt16(s[0]) | (UInt16(s[1]) << 8)
    }

    mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }

    mutating func u32() throws -> UInt32 {
        let s = Array(try take(4))
        var v: UInt32 = 0
        for i in (0..<4).reversed() { v = (v << 8) | UInt32(s[i]) }
        return v
    }

    mutating func u64() throws -> UInt64 {
        let s = Array(try take(8))
        var v: UInt64 = 0
        for i in (0..<8).reversed() { v = (v << 8) | UInt64(s[i]) }
        return v
    }

    mutating func data(_ n: Int) throws -> Data { Data(try take(n)) }

    mutating func rest() -> Data {
        let d = Data(bytes[offset...])
        offset = bytes.count
        return d
    }

    mutating func string8() throws -> String {
        let n = Int(try u8())
        return try string(n)
    }

    mutating func string16() throws -> String {
        let n = Int(try u16())
        return try string(n)
    }

    private mutating func string(_ n: Int) throws -> String {
        let d = try data(n)
        guard let s = String(data: d, encoding: .utf8) else { throw IucmProtocolError.invalidUTF8 }
        return s
    }

    /// Rejects payloads that carry more bytes than the layout defines.
    func expectEnd() throws {
        guard isAtEnd else {
            throw IucmProtocolError.trailingBytes(type: messageType, count: remaining)
        }
    }
}
