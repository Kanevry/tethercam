import Foundation

/// Stateless encode/decode of IUCM messages.
public enum IucmCodec {

    // MARK: - Encoding

    /// Serialises a message including its 12-byte header.
    public static func encode(_ message: IucmMessage) throws -> Data {
        var w = ByteWriter()
        var flags: UInt8 = 0

        switch message {
        case .hello(let m):
            w.u16(m.version)
            try w.string8(m.deviceName)
            try w.string8(m.appVersion)
            guard m.cameras.count <= 255 else { throw IucmProtocolError.stringTooLong(m.cameras.count) }
            w.u8(UInt8(m.cameras.count))
            for cam in m.cameras {
                w.u8(cam.id)
                w.u8(cam.position.rawValue)
                try w.string8(cam.name)
            }
        case .start(let m):
            w.u8(m.cameraId)
            w.u16(m.width)
            w.u16(m.height)
            w.u16(m.fps)
            w.u32(m.bitrateKbps)
        case .stop:
            break
        case .config(let m):
            w.u16(m.width)
            w.u16(m.height)
            w.u16(m.fps)
            w.u32(UInt32(m.hvcc.count))
            w.raw(m.hvcc)
        case .video(let m):
            flags = m.isKeyframe ? 0x01 : 0x00
            w.u64(m.ptsUs)
            w.raw(m.nalData)
        case .ping(let ts), .pong(let ts):
            w.u64(ts)
        case .error(let m):
            w.u16(m.code)
            try w.string16(m.text)
        }

        let payload = w.bytes
        guard payload.count <= Iucm.maxPayloadSize else {
            throw IucmProtocolError.payloadTooLarge(payload.count)
        }

        var header = ByteWriter()
        header.raw(Iucm.magic)
        header.u8(message.type.rawValue)
        header.u8(flags)
        header.u16(0) // reserved
        header.u32(UInt32(payload.count))

        var out = Data(header.bytes)
        out.append(contentsOf: payload)
        return out
    }

    // MARK: - Decoding

    /// Decodes a payload for an already-parsed header.
    public static func decodePayload(type rawType: UInt8, flags: UInt8, payload: [UInt8]) throws -> IucmMessage {
        guard let type = IucmMessageType(rawValue: rawType) else {
            throw IucmProtocolError.unknownType(rawType)
        }
        var r = ByteReader(payload, type: rawType)

        switch type {
        case .hello:
            let version = try r.u16()
            let deviceName = try r.string8()
            let appVersion = try r.string8()
            let count = Int(try r.u8())
            var cameras: [CameraInfo] = []
            cameras.reserveCapacity(count)
            for _ in 0..<count {
                let id = try r.u8()
                let posRaw = try r.u8()
                guard let pos = CameraPosition(rawValue: posRaw) else {
                    throw IucmProtocolError.invalidCameraPosition(posRaw)
                }
                let name = try r.string8()
                cameras.append(CameraInfo(id: id, position: pos, name: name))
            }
            try r.expectEnd()
            return .hello(HelloMessage(version: version, deviceName: deviceName,
                                       appVersion: appVersion, cameras: cameras))

        case .start:
            let m = StartMessage(cameraId: try r.u8(), width: try r.u16(), height: try r.u16(),
                                 fps: try r.u16(), bitrateKbps: try r.u32())
            try r.expectEnd()
            return .start(m)

        case .stop:
            try r.expectEnd()
            return .stop

        case .config:
            let width = try r.u16()
            let height = try r.u16()
            let fps = try r.u16()
            let len = Int(try r.u32())
            let hvcc = try r.data(len)
            try r.expectEnd()
            return .config(ConfigMessage(width: width, height: height, fps: fps, hvcc: hvcc))

        case .video:
            let pts = try r.u64()
            // Everything after pts is passed through verbatim to the decoder.
            return .video(VideoMessage(ptsUs: pts, isKeyframe: (flags & 0x01) != 0, nalData: r.rest()))

        case .ping:
            let ts = try r.u64()
            try r.expectEnd()
            return .ping(ts)

        case .pong:
            let ts = try r.u64()
            try r.expectEnd()
            return .pong(ts)

        case .error:
            let code = try r.u16()
            let text = try r.string16()
            try r.expectEnd()
            return .error(ErrorMessage(code: code, text: text))
        }
    }

    /// Convenience round-trip helper: decodes a single complete framed message.
    public static func decode(_ data: Data) throws -> IucmMessage {
        var parser = IucmFrameParser()
        let messages = try parser.append(data)
        guard let first = messages.first, messages.count == 1, parser.bufferedByteCount == 0 else {
            throw IucmProtocolError.truncatedPayload(type: 0)
        }
        return first
    }
}
