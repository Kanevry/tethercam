import Foundation

// usbcam-sim — sender simulator for the IUCM protocol.
//
//   usbcam-sim [--bind 127.0.0.1] [--port 7878] [--dump out.hevc]

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: usbcam-sim [--bind HOST] [--port PORT] [--dump FILE]

      --bind HOST   local address to listen on (default 127.0.0.1)
      --port PORT   TCP port (default 7878)
      --dump FILE   also write the encoded stream as Annex-B HEVC for ffmpeg/ffplay

    """.utf8))
    exit(2)
}

var bindHost = "127.0.0.1"
var port: UInt16 = 7878
var dumpPath: String?

var args = Array(CommandLine.arguments.dropFirst())
while let arg = args.first {
    args.removeFirst()
    switch arg {
    case "--bind":
        guard let v = args.first else { usage() }
        args.removeFirst(); bindHost = v
    case "--port":
        guard let v = args.first, let p = UInt16(v) else { usage() }
        args.removeFirst(); port = p
    case "--dump":
        guard let v = args.first else { usage() }
        args.removeFirst(); dumpPath = v
    case "-h", "--help":
        usage()
    default:
        FileHandle.standardError.write(Data("unknown option: \(arg)\n".utf8))
        usage()
    }
}

let server = SimServer(bindHost: bindHost, port: port, dumpPath: dumpPath)
do {
    try server.start()
} catch {
    log("startup failed: \(error)")
    exit(1)
}
dispatchMain()
