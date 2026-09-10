// AppState.swift
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer

import Combine
import Foundation
import OSLog
import ServiceManagement
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

    /// UserDefaults key for "the user pressed Done in the setup guide".
    static let didCompleteSetupKey = "didCompleteSetup"

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
        didSet {
            report("extension: \(extensionState.label)")
            // Only a real transition may pull the setup window forward; the
            // installer re-reports the same state while approval is pending.
            refreshOnboarding(stateChanged: oldValue != extensionState)
        }
    }
    /// Live pipeline snapshot; every change is one stderr line in headless mode.
    @Published var status = PipelineStatus() {
        didSet { report(status.line) }
    }

    /// True while the setup guide window should be on screen. `TetherCamApp`
    /// observes it and opens the window; the guide itself clears it.
    @Published var isShowingOnboarding = false
    /// Mirrors `SMAppService.mainApp.status`; nil while unknown.
    @Published var launchAtLogin = false
    /// Set when registering or unregistering the login item failed; the menu
    /// shows the sentence instead of throwing.
    @Published var launchAtLoginError: String?

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

    /// Raw frame counters belong to diagnostics, not to the normal menu: they
    /// look alarming while idle (see `PipelineStatus.noConsumer`). Shown only in
    /// the modes that exist for debugging anyway.
    var showsCounters: Bool { debugTCP != nil || headless }

    /// Idempotent entry point: submits the extension activation and starts the
    /// receive pipeline.
    func start() {
        guard !started else { return }
        started = true
        refreshLaunchAtLogin()
        // First evaluation of the launch counts as a transition.
        refreshOnboarding(stateChanged: true)
        if activateOnStart { installExtension() }
        startPipeline()
    }

    // MARK: - Setup guide

    /// "Done" was pressed in a previous run.
    var hasCompletedSetup: Bool {
        get { UserDefaults.standard.bool(forKey: Self.didCompleteSetupKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.didCompleteSetupKey) }
    }

    /// Set by "Done" for the rest of this launch, so an unapproved extension
    /// cannot keep re-presenting the guide. Deliberately not persisted: the next
    /// launch re-evaluates `hasCompletedSetup` from UserDefaults.
    private var onboardingSuppressedThisLaunch = false

    /// Applies `OnboardingPolicy` to the current state. Never opens the window
    /// in --headless mode; the policy is the single place that rule lives.
    ///
    /// - Parameter stateChanged: false when the extension state was re-reported
    ///   unchanged, in which case nothing is presented.
    func refreshOnboarding(stateChanged: Bool) {
        guard OnboardingPolicy.shouldPresentAutomatically(
            extensionEnabled: extensionState == .enabled,
            hasCompletedSetup: hasCompletedSetup,
            headless: headless,
            stateChanged: stateChanged,
            suppressedThisLaunch: onboardingSuppressedThisLaunch) else { return }
        showOnboarding()
    }

    /// Menu item "Setup guide…": always opens, even on a healthy install.
    func showOnboarding() {
        guard !headless else { return }
        isShowingOnboarding = true
        OnboardingWindowController.shared.present(state: self)
    }

    /// "Done" in the guide: remember it and close. The guide stays closed for
    /// the rest of this launch even while the extension is unapproved; the menu
    /// item "Setup guide…" still opens it on demand.
    func completeOnboarding() {
        hasCompletedSetup = true
        onboardingSuppressedThisLaunch = true
        isShowingOnboarding = false
        OnboardingWindowController.shared.close()
    }

    /// True when the app runs from /Applications — the only location from which
    /// macOS installs a system extension (App Translocation aside).
    var isInApplicationsFolder: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    /// "1.0 (7)" from the bundle; the About row and CLIENT_INFO use it.
    var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    // MARK: - Launch at Login

    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the login item. A denial in System Settings
    /// surfaces as `launchAtLoginError`, not as a thrown error.
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "macOS refused to change the login item — allow TetherCam in "
                + "System Settings > General > Login Items."
            report("launch at login \(enabled ? "register" : "unregister") failed: \(error)")
        }
        refreshLaunchAtLogin()
    }

    // MARK: - Uninstall

    /// Submits the deactivation request for the camera extension. macOS asks the
    /// user to confirm; the resulting state lands in `extensionState`.
    func removeExtension() {
        let installer = ExtensionInstaller()
        installer.onChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                // A completed deactivation reports .activated (the request
                // finished), which would read as "enabled" in the menu.
                self.extensionState = state == .activated ? .notInstalled : Self.map(state)
            }
        }
        self.installer = installer
        installer.deactivate()
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
        let pipeline = CameraPipeline(endpoint: endpoint, clientVersion: versionString)
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
