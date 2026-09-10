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
            // Short form (11 byte) when there is nothing to say, so a 1.0 app that
            // rejects trailing bytes still understands a 1.1 receiver.
            if m.flags != 0 { w.u8(m.flags) }
        case .stop:
            break
        case .clientInfo(let m):
            w.u8(m.kind)
            try w.string8(m.name)
            try w.string8(m.version)
        case .stats(let m):
            w.i16(m.continuousAngleX10)
            w.u16(m.sector)
            w.i16(m.residualX10)
            w.u16(m.gravityMX1000)
            w.u16(m.levelerMsX10)
            w.u16(m.droppedFrames)
            w.u16(m.sourceWidth)
            w.u16(m.sourceHeight)
            w.u16(m.outputWidth)
            w.u16(m.outputHeight)
            w.u8(m.flags)
            w.u8(m.cameraId)
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
        case .audioConfig(let m):
            w.u32(m.sampleRate)
            w.u8(m.channels)
            w.u8(m.codec)
            guard m.asc.count <= 0xFFFF else { throw IucmProtocolError.stringTooLong(m.asc.count) }
            w.u16(UInt16(m.asc.count))
            w.raw(m.asc)
        case .audio(let m):
            w.u64(m.ptsUs)
            w.raw(m.frame)
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
            var m = StartMessage(cameraId: try r.u8(), width: try r.u16(), height: try r.u16(),
                                 fps: try r.u16(), bitrateKbps: try r.u32())
            // Protocol 1.1 appends a flags byte; 1.0 senders stop after 11 byte.
            // Anything beyond that belongs to a later minor version: ignore it (4.2).
            if !r.isAtEnd {
                m.flags = try r.u8()
                _ = r.rest()
            }
            return .start(m)

        case .stop:
            try r.expectEnd()
            return .stop

        case .clientInfo:
            let kind = try r.u8()
            let name = try r.string8()
            let version = try r.string8()
            // Trailing bytes belong to a later minor version: ignore them (4.11).
            _ = r.rest()
            return .clientInfo(ClientInfoMessage(kind: kind, name: name, version: version))

        case .stats:
            let m = StatsMessage(continuousAngleX10: try r.i16(), sector: try r.u16(),
                                 residualX10: try r.i16(), gravityMX1000: try r.u16(),
                                 levelerMsX10: try r.u16(), droppedFrames: try r.u16(),
                                 sourceWidth: try r.u16(), sourceHeight: try r.u16(),
                                 outputWidth: try r.u16(), outputHeight: try r.u16(),
                                 flags: try r.u8(), cameraId: try r.u8())
            try r.expectEnd()
            return .stats(m)

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

        case .audioConfig:
            let sampleRate = try r.u32()
            let channels = try r.u8()
            let codec = try r.u8()
            let ascLen = Int(try r.u16())
            let asc = try r.data(ascLen)
            try r.expectEnd()
            return .audioConfig(AudioConfigMessage(sampleRate: sampleRate, channels: channels,
                                                   codec: codec, asc: asc))

        case .audio:
            let pts = try r.u64()
            // Everything after pts is one raw AAC access unit, passed through verbatim.
            return .audio(AudioMessage(ptsUs: pts, frame: r.rest()))

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
