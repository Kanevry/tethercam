// AppState.swift
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer

import Combine
import Foundation
import OSLog
import TetherCamContract
import TetherCamCore

/// Observable state of the host app, shown by MenuBarView and printed to stderr
/// in --headless mode.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState(arguments: CommandLine.arguments)

    /// Skips the OSSystemExtension activation request (scripts that only want
    /// the pipeline, e.g. tests on a machine where approval is pending).
    static let noActivateFlag = "--no-activate"

    enum ExtensionState: Equatable {
        case notInstalled
        case requested
        case waitingForUser
        case enabled
        case error(String)

        var label: String {
            switch self {
            case .notInstalled: return "Camera extension not installed"
            case .requested: return "Installing camera extension"
            case .waitingForUser: return "Waiting for approval in System Settings"
            case .enabled: return "Camera extension enabled"
            case .error(let message): return "Error: \(message)"
            }
        }
    }

    @Published var extensionState: ExtensionState = .notInstalled {
        didSet { report("extension: \(extensionState.label)") }
    }
    /// Live pipeline snapshot; every change is one stderr line in headless mode.
    @Published var status = PipelineStatus() {
        didSet { report(status.line) }
    }

    /// HOST:PORT from `--debug-tcp`, nil when the usbmux path is used.
    let debugTCP: String?
    /// `--headless`: no interaction expected, state changes go to stderr.
    let headless: Bool
    let activateOnStart: Bool

    private let log = Logger(subsystem: TetherCamContract.hostBundleID, category: "state")
    private var installer: ExtensionInstaller?
    private var pipeline: CameraPipeline?
    private var started = false

    init(arguments: [String]) {
        headless = arguments.contains(TetherCamContract.headlessFlag)
        activateOnStart = !arguments.contains(Self.noActivateFlag)
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
        if activateOnStart { installExtension() }
        startPipeline()
    }

    /// Submits (or re-submits) the system extension activation request.
    func installExtension() {
        let installer = ExtensionInstaller()
        installer.onChange = { [weak self] state in
            // OSSystemExtensionRequest was created with queue: .main, but the
            // delegate contract is not annotated, so hop explicitly.
            Task { @MainActor in self?.extensionState = Self.map(state) }
        }
        self.installer = installer
        installer.activate()
    }

    /// Opens System Settings > Login Items & Extensions where the user approves
    /// the camera extension.
    func openExtensionSettings() {
        ExtensionInstaller.openSystemSettings()
    }

    private func startPipeline() {
        let endpoint: Endpoint
        if let debugTCP {
            guard let parsed = Self.parseHostPort(debugTCP) else {
                report("invalid --debug-tcp value '\(debugTCP)', expected HOST:PORT")
                return
            }
            endpoint = .tcp(host: parsed.host, port: parsed.port)
        } else {
            endpoint = .usbmux(serial: nil)
        }
        let pipeline = CameraPipeline(endpoint: endpoint)
        pipeline.onLog = { [log] line in log.info("\(line)") }
        pipeline.onStatus = { [weak self] st in
            Task { @MainActor in self?.status = st }
        }
        self.pipeline = pipeline
        pipeline.start()
    }

    static func map(_ state: ExtensionInstaller.State) -> ExtensionState {
        switch state {
        case .idle: return .notInstalled
        case .requested: return .requested
        case .needsUserApproval: return .waitingForUser
        case .activated: return .enabled
        case .willCompleteAfterReboot: return .error("restart the Mac to finish installing the camera extension")
        case .failed(let message): return .error(message)
        }
    }

    static func parseHostPort(_ text: String) -> (host: String, port: UInt16)? {
        guard let colon = text.lastIndex(of: ":"),
              let port = UInt16(text[text.index(after: colon)...]),
              colon > text.startIndex else { return nil }
        return (String(text[..<colon]), port)
    }

    private func report(_ message: String) {
        log.info("\(message)")
        if headless {
            FileHandle.standardError.write(Data("tethercam: \(message)\n".utf8))
        }
    }
}
