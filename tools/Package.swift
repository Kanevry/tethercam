// swift-tools-version:5.9
import PackageDescription

// Swift package for the obs-iphone-usb-cam developer tools.
//
// Targets:
//   IucmProtocol  — pure-Swift codec + stateful frame parser for the IUCM wire protocol.
//   usbcam-sim    — sender simulator (test pattern -> VideoToolbox HEVC -> TCP).
//   CUsbmux       — C-Target, das shared/usbmux.c per Shim-#include einbindet.
//   usbcam-recv   — CLI-Empfaenger (TCP oder usbmuxd-Tunnel).
let package = Package(
    name: "usbcam-tools",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "IucmProtocol", targets: ["IucmProtocol"]),
        .library(name: "CUsbmux", targets: ["CUsbmux"]),
        .executable(name: "usbcam-sim", targets: ["usbcam-sim"]),
        .executable(name: "usbcam-recv", targets: ["usbcam-recv"]),
    ],
    targets: [
        .target(name: "IucmProtocol"),
        .executableTarget(name: "usbcam-sim", dependencies: ["IucmProtocol"]),
        // Der Shim liegt unter Sources/CUsbmux, kompiliert aber ../../../shared/usbmux.c.
        .target(name: "CUsbmux"),
        .executableTarget(name: "usbcam-recv", dependencies: ["IucmProtocol", "CUsbmux"]),
        // Die Executables haengen mit drin, damit AacToneEncoder (sim) und
        // AacDecoder/Adts (recv) testbar sind, ohne Audio-Code in die Lib zu ziehen.
        .testTarget(name: "IucmProtocolTests",
                    dependencies: ["IucmProtocol", "usbcam-sim", "usbcam-recv"]),
    ]
)
