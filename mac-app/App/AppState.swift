// AppState.swift
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer

import Combine
import Foundation
import OSLog
import TetherCamContract

/// Observable state of the host app, shown by MenuBarView and printed to stderr
/// in --headless mode.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState(arguments: CommandLine.arguments)

    enum ExtensionState: Equatable {
        case notInstalled
        case waitingForUser
        case enabled
        case error(String)

        var label: String {
            switch self {
            case .notInstalled: return "Camera extension not installed"
            case .waitingForUser: return "Waiting for approval in System Settings"
            case .enabled: return "Camera extension enabled"
            case .error(let message): return "Error: \(message)"
            }
        }
    }

    @Published var extensionState: ExtensionState = .notInstalled {
        didSet { report("extension: \(extensionState.label)") }
    }
    @Published var linkState: String = "Waiting for iPhone" {
        didSet { report("link: \(linkState)") }
    }
    @Published var resolution: String = "-" {
        didSet { report("resolution: \(resolution)") }
    }

    /// HOST:PORT from `--debug-tcp`, nil when the usbmux path is used.
    let debugTCP: String?
    /// `--headless`: no interaction expected, state changes go to stderr.
    let headless: Bool

    private let log = Logger(subsystem: TetherCamContract.hostBundleID, category: "state")
    private var activation: ExtensionActivation?
    private var started = false

    init(arguments: [String]) {
        headless = arguments.contains(TetherCamContract.headlessFlag)
        if let index = arguments.firstIndex(of: TetherCamContract.debugTCPFlag),
           arguments.indices.contains(index + 1) {
            debugTCP = arguments[index + 1]
        } else {
            debugTCP = nil
        }
        if headless {
            report("headless mode, debug-tcp=\(debugTCP ?? "off")")
        }
    }

    /// Idempotent entry point: submits the extension activation and starts the
    /// receive pipeline.
    func start() {
        guard !started else { return }
        started = true
        installExtension()
        // TODO(W3): wire TetherCamCore — create Receiver (usbmux or debugTCP),
        // HevcDecoder and CMIOSink; update linkState/resolution from their callbacks.
    }

    /// Submits (or re-submits) the system extension activation request.
    func installExtension() {
        let activation = ExtensionActivation { [weak self] state in
            self?.extensionState = state
        }
        self.activation = activation
        activation.activate()
    }

    /// Opens System Settings > Login Items & Extensions where the user approves
    /// the camera extension.
    func openExtensionSettings() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["x-apple.systempreferences:com.apple.LoginItems-Settings.extension"]
        do {
            try process.run()
        } catch {
            log.error("open System Settings failed: \(error.localizedDescription)")
        }
    }

    private func report(_ message: String) {
        log.info("\(message)")
        if headless {
            FileHandle.standardError.write(Data("tethercam: \(message)\n".utf8))
        }
    }
}
