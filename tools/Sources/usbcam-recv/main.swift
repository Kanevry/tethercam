import Foundation
#if canImport(Darwin)
import Darwin
#endif

// usbcam-recv — CLI-Empfaenger fuer das IUCM-Protokoll (protocol/PROTOCOL.md).
//
//   usbcam-recv --tcp 127.0.0.1:7979 --seconds 5 --dump out.hevc --json
//   usbcam-recv --serial 00008130-... --seconds 3

struct Options {
    var tcp: (host: String, port: UInt16)?
    var serial: String?
    var port: UInt16 = 7878
    var camera: UInt8 = 0
    var width: UInt16 = 1920
    var height: UInt16 = 1080
    var fps: UInt16 = 30
    var bitrate: UInt32 = 12000
    var dumpPath: String?
    var audioDumpPath: String?
    /// START bit 0 — ask the sender for audio (default on, `--no-audio` clears it).
    var audio = true
    var seconds: Double?
    var json = false
    var helloTimeout: Double = 3.0
}

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: usbcam-recv [--tcp HOST:PORT | --serial UDID] [options]

      --tcp HOST:PORT   plain TCP statt usbmuxd (Simulator)
      --serial UDID     iPhone per Seriennummer; ohne Angabe das erste USB-Geraet
      --port PORT       Geraeteport im usbmux-Tunnel (Vorgabe 7878)
      --camera N        Kamera-ID aus HELLO (Vorgabe 0)
      --size WxH        Wunschformat (Vorgabe 1920x1080)
      --fps N           Wunsch-Bildrate (Vorgabe 30)
      --bitrate KBPS    Ziel-Bitrate (Vorgabe 12000)
      --dump FILE       Annex-B-HEVC mitschreiben (Parametersaetze vor jedem Keyframe)
      --dump-audio FILE AAC als ADTS mitschreiben (ffprobe-lesbar)
      --no-audio        kein Audio anfordern (START-Flag Bit 0 bleibt 0)
      --seconds N       nach N s STOP senden und mit 0 beenden
      --json            eine Zusammenfassungszeile als JSON auf stdout
      --hello-timeout S Wartezeit auf HELLO (Vorgabe 3)

    """.utf8))
    exit(2)
}

var opts = Options()
var args = Array(CommandLine.arguments.dropFirst())
func next(_ args: inout [String]) -> String { guard let v = args.first else { usage() }; args.removeFirst(); return v }

while let arg = args.first {
    args.removeFirst()
    switch arg {
    case "--tcp":
        let v = next(&args)
        guard let idx = v.lastIndex(of: ":"), let p = UInt16(v[v.index(after: idx)...]) else { usage() }
        opts.tcp = (String(v[v.startIndex..<idx]), p)
    case "--serial": opts.serial = next(&args)
    case "--port": guard let p = UInt16(next(&args)) else { usage() }; opts.port = p
    case "--camera": guard let c = UInt8(next(&args)) else { usage() }; opts.camera = c
    case "--size":
        let v = next(&args).lowercased()
        let parts = v.split(separator: "x")
        guard parts.count == 2, let w = UInt16(parts[0]), let h = UInt16(parts[1]) else { usage() }
        opts.width = w; opts.height = h
    case "--fps": guard let f = UInt16(next(&args)) else { usage() }; opts.fps = f
    case "--bitrate": guard let b = UInt32(next(&args)) else { usage() }; opts.bitrate = b
    case "--dump": opts.dumpPath = next(&args)
    case "--dump-audio": opts.audioDumpPath = next(&args)
    case "--no-audio": opts.audio = false
    case "--seconds": guard let s = Double(next(&args)) else { usage() }; opts.seconds = s
    case "--hello-timeout": guard let s = Double(next(&args)) else { usage() }; opts.helloTimeout = s
    case "--json": opts.json = true
    case "-h", "--help": usage()
    default:
        FileHandle.standardError.write(Data("unknown option: \(arg)\n".utf8))
        usage()
    }
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(msg)\n".utf8))
    exit(1)
}

// SIGPIPE wuerde den Prozess killen, sobald die Gegenseite zumacht.
signal(SIGPIPE, SIG_IGN)

var fd: Int32 = -1
do {
    if let tcp = opts.tcp {
        fd = try Transport.connectTCP(host: tcp.host, port: tcp.port)
        logLine("LINK    tcp \(tcp.host):\(tcp.port) connected (fd \(fd))")
    } else {
        let devices = try Transport.listDevices()
        guard !devices.isEmpty else { fail("no USB device attached (usbmux ListDevices returned 0 USB entries)") }
        let device: DeviceRef
        if let serial = opts.serial {
            guard let d = devices.first(where: { $0.serial.caseInsensitiveCompare(serial) == .orderedSame }) else {
                fail("serial \(serial) not found among USB devices: \(devices.map { $0.serial })")
            }
            device = d
        } else {
            device = devices[0]
        }
        fd = try Transport.connectUsbmux(device: device, port: opts.port)
        logLine("LINK    usbmux tunnel open: DeviceID \(device.deviceId) serial \(device.serial) port \(opts.port) (fd \(fd))")
    }
} catch {
    fail("\(error)")
}

do {
    let recv = try Receiver(fd: fd, opts: opts)
    let summary = try recv.run()
    close(fd)
    if opts.json {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(summary)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    } else {
        logLine(String(format: "SUMMARY frames=%d fps=%.1f kbps=%.0f keyframes=%d rtt=%.1f ms first_frame=%.0f ms nals=%d",
                       summary.frames, summary.fps_avg, summary.kbps_avg, summary.keyframes,
                       summary.ping_rtt_ms_avg, summary.first_frame_ms, summary.nals))
        logLine(String(format: "AUDIO   frames=%d samples=%d rate=%d first_frame=%.0f ms skew=%.1f ms",
                       summary.audio_frames, summary.audio_decoded_samples,
                       summary.audio_sample_rate, summary.audio_first_frame_ms,
                       summary.audio_video_pts_skew_ms))
    }
    exit(0)
} catch {
    close(fd)
    fail("\(error)")
}
