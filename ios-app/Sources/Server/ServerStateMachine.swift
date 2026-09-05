import Foundation

/// Pure, testable core of the USB server: events in, actions out.
///
/// Deliberately free of Network framework types so the whole connection
/// lifecycle (HELLO before START, BUSY on a second connection, 6-second PING
/// timeout) can be unit tested without a socket.
public struct ServerStateMachine: Equatable {

    public enum Phase: Equatable {
        case idle          // listening, no connection
        case greeted       // connection accepted, HELLO sent, not streaming
        case streaming(StartParams)
    }

    public enum Event: Equatable {
        case connectionAccepted(id: UInt64, nowUs: UInt64)
        case message(IucmMessage, nowUs: UInt64)
        case connectionClosed(id: UInt64)
        case tick(nowUs: UInt64)
        case captureFailed(IucmErrorCode, text: String)
    }

    public enum Action: Equatable {
        case send(IucmMessage, to: UInt64)
        case close(id: UInt64)
        case startCapture(StartParams)
        case stopCapture
    }

    /// No PING for this long means the receiver is gone (spec section 4).
    public static let pingTimeoutUs: UInt64 = 6_000_000

    public private(set) var phase: Phase = .idle
    public private(set) var activeConnection: UInt64?
    public private(set) var lastPingUs: UInt64 = 0

    private let deviceName: String
    private let appVersion: String
    private let cameras: [CameraDescriptor]

    public init(deviceName: String, appVersion: String, cameras: [CameraDescriptor]) {
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.cameras = cameras
    }

    public var isStreaming: Bool {
        if case .streaming = phase { return true }
        return false
    }

    public mutating func handle(_ event: Event) -> [Action] {
        switch event {

        case let .connectionAccepted(id, nowUs):
            guard activeConnection == nil else {
                // Exactly one receiver per device: refuse and close (spec section 3).
                return [.send(.error(code: IucmErrorCode.busy.rawValue,
                                     text: "another receiver is connected"), to: id),
                        .close(id: id)]
            }
            activeConnection = id
            lastPingUs = nowUs
            phase = .greeted
            // HELLO is sent immediately on accept, before any START can arrive.
            return [.send(.hello(version: Iucm.version, deviceName: deviceName,
                                 appVersion: appVersion, cameras: cameras), to: id)]

        case let .message(msg, nowUs):
            guard let conn = activeConnection else { return [] }
            switch msg {
            case let .start(p):
                guard cameras.contains(where: { $0.id == p.cameraId }) else {
                    return [.send(.error(code: IucmErrorCode.formatUnsupported.rawValue,
                                         text: "unknown camera id \(p.cameraId)"), to: conn)]
                }
                var actions: [Action] = []
                if isStreaming { actions.append(.stopCapture) }   // restart with new params
                phase = .streaming(p)
                actions.append(.startCapture(p))
                return actions
            case .stop:
                guard isStreaming else { return [] }
                phase = .greeted
                return [.stopCapture]
            case let .ping(ts):
                lastPingUs = nowUs
                return [.send(.pong(timestampUs: ts), to: conn)]
            case .error:
                // Receiver reported a fatal condition: tear the connection down.
                return teardown(conn)
            default:
                // HELLO/CONFIG/VIDEO/PONG are app->mac only; ignore if echoed back.
                return []
            }

        case let .connectionClosed(id):
            guard id == activeConnection else { return [] }
            let wasStreaming = isStreaming
            activeConnection = nil
            phase = .idle
            return wasStreaming ? [.stopCapture] : []

        case let .tick(nowUs):
            guard let conn = activeConnection else { return [] }
            guard nowUs >= lastPingUs,
                  nowUs - lastPingUs >= Self.pingTimeoutUs else { return [] }
            // Dead link: free the listener so a new receiver is not stuck on BUSY.
            return teardown(conn)

        case let .captureFailed(code, text):
            guard let conn = activeConnection else { return [] }
            let wasStreaming = isStreaming
            phase = .greeted
            var actions: [Action] = wasStreaming ? [.stopCapture] : []
            actions.append(.send(.error(code: code.rawValue, text: text), to: conn))
            return actions
        }
    }

    private mutating func teardown(_ conn: UInt64) -> [Action] {
        let wasStreaming = isStreaming
        activeConnection = nil
        phase = .idle
        var actions: [Action] = wasStreaming ? [.stopCapture] : []
        actions.append(.close(id: conn))
        return actions
    }
}
