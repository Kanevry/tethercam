// swift-tools-version: 5.9
// TetherCam for macOS: core library (receiver, decoder, scaler, CMIO sink bridge).
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "TetherCamCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TetherCamContract", targets: ["TetherCamContract"]),
        .library(name: "TetherCamCore", targets: ["TetherCamCore"]),
    ],
    dependencies: [
        .package(name: "usbcam-tools", path: "../../tools"),
    ],
    targets: [
        .target(name: "TetherCamContract"),
        .target(
            name: "TetherCamCore",
            dependencies: [
                "TetherCamContract",
                .product(name: "IucmProtocol", package: "usbcam-tools"),
                .product(name: "CUsbmux", package: "usbcam-tools"),
            ]
        ),
        .testTarget(name: "TetherCamCoreTests", dependencies: ["TetherCamCore"]),
    ]
)
