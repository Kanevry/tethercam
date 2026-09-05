import Foundation

/// Stateful byte-stream framer. Feed arbitrary chunks, get whole messages back.
///
/// Handles the three hostile cases the spec calls out: partial frames spread over
/// several reads, garbage before the magic (resync), and an over-long length field.
public struct IucmFrameParser {
    private var buffer: [UInt8] = []
    /// Number of bytes held back waiting for more input.
    public var bufferedByteCount: Int { buffer.count }
    /// Bytes discarded during resync, for diagnostics.
    public private(set) var resyncDroppedBytes: Int = 0

    public init() {}

    public mutating func append(_ data: Data) throws -> [IucmMessage] {
        buffer.append(contentsOf: data)
        return try drain()
    }

    private mutating func drain() throws -> [IucmMessage] {
        var out: [IucmMessage] = []

        while true {
            try resyncToMagic()
            guard buffer.count >= Iucm.headerSize else { break }

            let rawType = buffer[4]
            let flags = buffer[5]
            var length: UInt32 = 0
            for i in (8..<12).reversed() { length = (length << 8) | UInt32(buffer[i]) }

            guard length <= UInt32(Iucm.maxPayloadSize) else {
                throw IucmProtocolError.payloadTooLarge(Int(length))
            }
            let total = Iucm.headerSize + Int(length)
            guard buffer.count >= total else { break }

            let payload = Array(buffer[Iucm.headerSize..<total])
            buffer.removeFirst(total)
            out.append(try IucmCodec.decodePayload(type: rawType, flags: flags, payload: payload))
        }
        return out
    }

    /// Drops leading bytes until the buffer starts with the magic, or until fewer
    /// than 4 bytes remain (a magic could still straddle the next read).
    private mutating func resyncToMagic() throws {
        if buffer.count >= 4 && Array(buffer[0..<4]) == Iucm.magic { return }
        var i = 0
        while i + 4 <= buffer.count {
            if Array(buffer[i..<(i + 4)]) == Iucm.magic { break }
            i += 1
        }
        if i + 4 <= buffer.count {
            if i > 0 { buffer.removeFirst(i); resyncDroppedBytes += i }
        } else {
            // Keep the last 3 bytes: they may be a split magic prefix.
            let keep = min(3, buffer.count)
            let drop = buffer.count - keep
            if drop > 0 { buffer.removeFirst(drop); resyncDroppedBytes += drop }
        }
    }
}
