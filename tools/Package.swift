// swift-tools-version:5.9
import PackageDescription

// Swift package for the obs-iphone-usb-cam developer tools.
//
// Targets:
//   IucmProtocol  — pure-Swift codec + stateful frame parser for the IUCM wire protocol.
//   usbcam-sim    — sender simulator (test pattern -> VideoToolbox HEVC -> TCP).
//
// A `usbcam-recv` executable target is added here later; keep this manifest flat.
let package = Package(
    name: "usbcam-tools",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "IucmProtocol", targets: ["IucmProtocol"]),
        .executable(name: "usbcam-sim", targets: ["usbcam-sim"]),
    ],
    targets: [
        .target(name: "IucmProtocol"),
        .executableTarget(name: "usbcam-sim", dependencies: ["IucmProtocol"]),
        .testTarget(name: "IucmProtocolTests", dependencies: ["IucmProtocol"]),
    ]
)
