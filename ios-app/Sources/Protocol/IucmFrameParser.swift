import Foundation

/// Stateful byte-stream framer. Feed arbitrary chunks, get complete messages.
///
/// Resync policy (spec section 8): if the first 4 bytes are not the magic, or a
/// header announces a payload above `Iucm.maxPayload`, we scan forward for the
/// next occurrence of "IUCM" and drop everything before it. The caller can see
/// how much was discarded via `resyncCount` / `droppedBytes` and decide whether
/// to log or to close the connection.
public final class IucmFrameParser {
    public struct Frame: Equatable {
        public var type: UInt8
        public var flags: UInt8
        public var payload: Data
    }

    public enum ParseError: Error, Equatable {
        case oversizedPayload(UInt32)
        case decode(IucmDecodeError)
    }

    private var buffer = [UInt8]()
    public private(set) var resyncCount = 0
    public private(set) var droppedBytes = 0

    public init() {}

    public var bufferedByteCount: Int { buffer.count }

    public func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    /// Appends `data` and returns every frame that is now complete.
    /// Throws only on an oversized length field; junk bytes are resynced silently.
    public func feed(_ data: Data) throws -> [Frame] {
        buffer.append(contentsOf: data)
        var out: [Frame] = []

        while true {
            // Resync: ensure the buffer starts on a magic.
            if buffer.count >= 1, !startsWithMagicPrefix() {
                guard resync() else { return out }
            }
            guard buffer.count >= Iucm.headerSize else { return out }
            // A partial-but-matching prefix shorter than 4 bytes cannot be judged yet.
            guard Array(buffer[0..<4]) == Iucm.magic else {
                guard resync() else { return out }
                continue
            }
            var len: UInt32 = 0
            for k in 0..<4 { len |= UInt32(buffer[8 + k]) << (8 * UInt32(k)) }
            if len > UInt32(Iucm.maxPayload) {
                // Corrupt framing. Drop this magic and look for the next one.
                buffer.removeFirst(4)
                droppedBytes += 4
                resyncCount += 1
                throw ParseError.oversizedPayload(len)
            }
            let total = Iucm.headerSize + Int(len)
            guard buffer.count >= total else { return out }
            out.append(Frame(type: buffer[4], flags: buffer[5],
                             payload: Data(buffer[Iucm.headerSize..<total])))
            buffer.removeFirst(total)
        }
    }

    /// Feed + decode in one step. Frames whose payload fails to decode are
    /// reported via `onDecodeError` and skipped, so one bad message does not
    /// desynchronise the stream (the framing was still valid).
    public func feedMessages(_ data: Data,
                             onDecodeError: ((IucmDecodeError) -> Void)? = nil) throws -> [IucmMessage] {
        try feed(data).compactMap { f in
            do {
                return try IucmCodec.decodePayload(type: f.type, flags: f.flags, payload: f.payload)
            } catch let e as IucmDecodeError {
                onDecodeError?(e)
                return nil
            } catch {
                return nil
            }
        }
    }

    /// True when the buffer's head could still become a magic (full or partial match).
    private func startsWithMagicPrefix() -> Bool {
        let n = min(4, buffer.count)
        for k in 0..<n where buffer[k] != Iucm.magic[k] { return false }
        return true
    }

    /// Drops bytes until the next possible magic start. Returns false when the
    /// buffer is exhausted (or only holds a partial magic prefix at the end).
    private func resync() -> Bool {
        var i = 1
        while i < buffer.count {
            if buffer[i] == Iucm.magic[0] {
                let n = min(4, buffer.count - i)
                var ok = true
                for k in 0..<n where buffer[i + k] != Iucm.magic[k] { ok = false; break }
                if ok { break }
            }
            i += 1
        }
        let drop = min(i, buffer.count)
        buffer.removeFirst(drop)
        droppedBytes += drop
        resyncCount += 1
        return buffer.count >= 1 && startsWithMagicPrefix()
    }
}
