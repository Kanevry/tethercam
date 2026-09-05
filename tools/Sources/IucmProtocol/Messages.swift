import Foundation

/// Wire-protocol constants. See `protocol/PROTOCOL.md`.
public enum Iucm {
    /// ASCII "IUCM".
    public static let magic: [UInt8] = [0x49, 0x55, 0x43, 0x4D]
    /// Fixed header size in bytes.
    public static let headerSize = 12
    /// Protocol version 1.0 — high byte major, low byte minor.
    public static let version: UInt16 = 0x0100
    /// Payloads larger than this are rejected as corrupt rather than buffered.
    public static let maxPayloadSize = 16 * 1024 * 1024
    /// A sender drops a connection that has not sent a PING for this long.
    public static let pingTimeout: TimeInterval = 6.0
}

public enum IucmMessageType: UInt8, Sendable {
    case hello = 0x01
    case start = 0x02
    case stop = 0x03
    case stats = 0x12
    case config = 0x10
    case video = 0x11
    case ping = 0x20
    case pong = 0x21
    case error = 0x30
}

public enum CameraPosition: UInt8, Sendable {
    case back = 0
    case front = 1
}

public struct CameraInfo: Equatable, Sendable {
    public var id: UInt8
    public var position: CameraPosition
    public var name: String

    public init(id: UInt8, position: CameraPosition, name: String) {
        self.id = id
        self.position = position
        self.name = name
    }
}

public struct HelloMessage: Equatable, Sendable {
    public var version: UInt16
    public var deviceName: String
    public var appVersion: String
    public var cameras: [CameraInfo]

    public init(version: UInt16 = Iucm.version, deviceName: String, appVersion: String, cameras: [CameraInfo]) {
        self.version = version
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.cameras = cameras
    }
}

public struct StartMessage: Equatable, Sendable {
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

public struct ConfigMessage: Equatable, Sendable {
    public var width: UInt16
    public var height: UInt16
    public var fps: UInt16
    /// Raw `hvcC` record, taken verbatim from the encoder's format description.
    public var hvcc: Data

    public init(width: UInt16, height: UInt16, fps: UInt16, hvcc: Data) {
        self.width = width
        self.height = height
        self.fps = fps
        self.hvcc = hvcc
    }
}

/// STATS (`0x12`), app to Mac. See `protocol/PROTOCOL.md` section 4.8.
///
/// Fixed-point on the wire so a decoded message round-trips byte-identically.
public struct StatsMessage: Equatable, Sendable {
    public static let flagAutoRotation: UInt8 = 1 << 0
    public static let flagHorizonLeveling: UInt8 = 1 << 1
    public static let flagOversampling: UInt8 = 1 << 2
    public static let flagFlatHold: UInt8 = 1 << 3

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

    public var continuousDeg: Double { Double(continuousAngleX10) / 10 }
    public var residualDeg: Double { Double(residualX10) / 10 }
    public var gravityM: Double { Double(gravityMX1000) / 1000 }
    public var levelerMs: Double { Double(levelerMsX10) / 10 }
}

public struct VideoMessage: Equatable, Sendable {
    public var ptsUs: UInt64
    public var isKeyframe: Bool
    /// VCL NAL units, 4-byte big-endian length prefixed (HVCC style). No parameter sets.
    public var nalData: Data

    public init(ptsUs: UInt64, isKeyframe: Bool, nalData: Data) {
        self.ptsUs = ptsUs
        self.isKeyframe = isKeyframe
        self.nalData = nalData
    }
}

public enum IucmErrorCode: UInt16, Sendable {
    case busy = 1
    case cameraDenied = 2
    case formatUnsupported = 3
    case encoderFailed = 4
    case versionUnsupported = 5
}

public struct ErrorMessage: Equatable, Sendable {
    public var code: UInt16
    public var text: String

    public init(code: UInt16, text: String) {
        self.code = code
        self.text = text
    }

    public init(_ code: IucmErrorCode, _ text: String) {
        self.init(code: code.rawValue, text: text)
    }
}

public enum IucmMessage: Equatable, Sendable {
    case hello(HelloMessage)
    case start(StartMessage)
    case stop
    case stats(StatsMessage)
    case config(ConfigMessage)
    case video(VideoMessage)
    case ping(UInt64)
    case pong(UInt64)
    case error(ErrorMessage)

    public var type: IucmMessageType {
        switch self {
        case .hello: return .hello
        case .start: return .start
        case .stop: return .stop
        case .stats: return .stats
        case .config: return .config
        case .video: return .video
        case .ping: return .ping
        case .pong: return .pong
        case .error: return .error
        }
    }
}

public enum IucmProtocolError: Error, Equatable {
    case truncatedPayload(type: UInt8)
    case trailingBytes(type: UInt8, count: Int)
    case unknownType(UInt8)
    case invalidUTF8
    case payloadTooLarge(Int)
    case invalidCameraPosition(UInt8)
    case stringTooLong(Int)
}
