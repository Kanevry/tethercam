// SPDX-License-Identifier: MIT
// Transport.swift
// TetherCam for macOS: socket plumbing for the receiver. Ported from
// tools/Sources/usbcam-recv/Transport.swift (same author, MIT) and extended with
// the socket options the OBS plugin also applies (TCP_NODELAY, bounded send).

import CUsbmux
import Darwin
import Foundation

public enum TransportError: Error, CustomStringConvertible, Sendable {
    case tcp(String)
    case usbmux(String)

    public var description: String {
        switch self {
        case .tcp(let m): return "TCP: \(m)"
        case .usbmux(let m): return "usbmux: \(m)"
        }
    }
}

/// One USB-attached iOS device as reported by usbmuxd.
public struct DeviceRef: Equatable, Sendable {
    public var deviceId: UInt32
    public var serial: String

    public init(deviceId: UInt32, serial: String) {
        self.deviceId = deviceId
        self.serial = serial
    }
}

/// Where the receiver connects to. `.tcp` bypasses usbmuxd (usbcam-sim, debugging);
/// `.usbmux` is the production path over the USB cable.
public enum Endpoint: Equatable, Sendable {
    case tcp(host: String, port: UInt16)
    /// `serial == nil` picks the first attached device.
    case usbmux(serial: String?)

    public static let iucmPort: UInt16 = 7878
    public static let defaultDebugTCP: Endpoint = .tcp(host: "127.0.0.1", port: iucmPort)
}

enum Transport {

    /// Plain TCP. Blocking connect; the caller runs on its own thread.
    static func connectTCP(host: String, port: UInt16) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(host, String(port), &hints, &res)
        guard rc == 0, let list = res else {
            throw TransportError.tcp("getaddrinfo(\(host)): \(String(cString: gai_strerror(rc)))")
        }
        defer { freeaddrinfo(list) }
        var node: UnsafeMutablePointer<addrinfo>? = list
        var lastErr = "no address"
        while let ai = node {
            let fd = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
            if fd >= 0 {
                if Darwin.connect(fd, ai.pointee.ai_addr, ai.pointee.ai_addrlen) == 0 { return fd }
                lastErr = String(cString: strerror(errno))
                close(fd)
            } else {
                lastErr = String(cString: strerror(errno))
            }
            node = ai.pointee.ai_next
        }
        throw TransportError.tcp("connect \(host):\(port) failed: \(lastErr)")
    }

    /// USB devices only: usbmux_list_devices() drops the Network twin (PROTOCOL.md 6.5).
    static func listDevices() throws -> [DeviceRef] {
        var raw = [usbmux_device](repeating: usbmux_device(), count: 32)
        var count = 0
        let rc = raw.withUnsafeMutableBufferPointer { buf in
            usbmux_list_devices(buf.baseAddress, buf.count, &count)
        }
        guard rc == USBMUX_OK else {
            throw TransportError.usbmux("list_devices: \(String(cString: usbmux_strerror(rc)))")
        }
        return raw.prefix(count).map { dev in
            var d = dev
            let serial = withUnsafeBytes(of: &d.serial) { rawBuf -> String in
                let p = rawBuf.bindMemory(to: CChar.self)
                return String(cString: p.baseAddress!)
            }
            return DeviceRef(deviceId: dev.device_id, serial: serial)
        }
    }

    /// Opens the usbmuxd tunnel. `port` is in HOST order; htons happens inside
    /// usbmux_connect (PROTOCOL.md 6.3), never here.
    static func connectUsbmux(device: DeviceRef, port: UInt16) throws -> Int32 {
        var result: Int32 = -1
        let fd = usbmux_connect(device.deviceId, port, &result)
        guard fd >= 0 else {
            let hint = result == Int32(USBMUX_RESULT_REFUSED)
                ? " (Number 3: port closed or app not listening)"
                : (result >= 0 ? " (Number \(result))" : ": \(String(cString: strerror(errno)))")
            throw TransportError.usbmux("connect device \(device.deviceId) port \(port) failed\(hint)")
        }
        return fd
    }

    /// Result of one successful connect attempt on either path.
    struct ConnectResult {
        var fd: Int32
        var peer: String
    }

    /// One failed connect attempt. `deviceCount` is the number of USB devices seen on
    /// the usbmux path (splits noDevice from waiting) and always 1 on the TCP path.
    struct ConnectFailure: Error {
        var deviceCount: Int
        var message: String
    }

    /// One connect attempt on the given endpoint.
    static func connect(_ endpoint: Endpoint) -> Result<ConnectResult, ConnectFailure> {
        switch endpoint {
        case .tcp(let host, let port):
            do {
                let fd = try connectTCP(host: host, port: port)
                return .success(ConnectResult(fd: fd, peer: "\(host):\(port)"))
            } catch {
                return .failure(ConnectFailure(deviceCount: 1, message: "\(error)"))
            }
        case .usbmux(let serial):
            let devices: [DeviceRef]
            do { devices = try listDevices() } catch {
                return .failure(ConnectFailure(deviceCount: 0, message: "\(error)"))
            }
            let pick: DeviceRef?
            if let serial, !serial.isEmpty {
                pick = devices.first { $0.serial == serial }
            } else {
                pick = devices.first
            }
            guard let device = pick else {
                return .failure(ConnectFailure(deviceCount: devices.count,
                                               message: devices.isEmpty ? "no USB device" : "serial not attached"))
            }
            do {
                let fd = try connectUsbmux(device: device, port: Endpoint.iucmPort)
                return .success(ConnectResult(fd: fd, peer: device.serial))
            } catch {
                return .failure(ConnectFailure(deviceCount: devices.count, message: "\(error)"))
            }
        }
    }

    /// TCP_NODELAY so PING/START leave immediately; SO_SNDTIMEO bounds a blocking
    /// send() so a wedged peer cannot pin the receiver thread where stop() cannot
    /// reach it.
    static func tuneSocket(_ fd: Int32, sendTimeoutMs: Int) {
        var one: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: sendTimeoutMs / 1000, tv_usec: Int32((sendTimeoutMs % 1000) * 1000))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Writes all of `data`, retrying on EINTR. Throws on EOF or a send timeout.
    static func sendAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: off), raw.count - off)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw TransportError.tcp("write: \(String(cString: strerror(errno)))")
                }
                if n == 0 { throw TransportError.tcp("write returned 0") }
                off += n
            }
        }
    }
}
