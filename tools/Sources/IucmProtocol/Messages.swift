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
