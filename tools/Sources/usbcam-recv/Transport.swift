import Foundation
import CUsbmux
#if canImport(Darwin)
import Darwin
#endif

enum TransportError: Error, CustomStringConvertible {
    case tcp(String)
    case usbmux(String)

    var description: String {
        switch self {
        case .tcp(let m): return "TCP: \(m)"
        case .usbmux(let m): return "usbmux: \(m)"
        }
    }
}

struct DeviceRef {
    var deviceId: UInt32
    var serial: String
}

enum Transport {

    /// Plain TCP, used with `--tcp host:port` against usbcam-sim.
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
                if connect(fd, ai.pointee.ai_addr, ai.pointee.ai_addrlen) == 0 { return fd }
                lastErr = String(cString: strerror(errno))
                close(fd)
            } else {
                lastErr = String(cString: strerror(errno))
            }
            node = ai.pointee.ai_next
        }
        throw TransportError.tcp("connect \(host):\(port) failed: \(lastErr)")
    }

    /// USB devices only — usbmux_list_devices() drops the Network twin (PROTOCOL.md 6.5).
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

    /// Opens the usbmuxd tunnel. `port` is in HOST order — htons happens inside
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
}
