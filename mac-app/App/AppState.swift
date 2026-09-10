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

    /// UserDefaults key for the update-check opt-out. Absent means on.
    static let automaticUpdateCheckKey = "checkForUpdatesAutomatically"

    enum ExtensionState: Equatable {
        case notInstalled
        case requested
        case waitingForUser
        /// macOS accepted the activation; the app is still probing whether a
        /// camera device really showed up. Transient — never a resting state.
        case verifyingDevice
        case enabled
        /// macOS reports the extension as activated, but started no camera
        /// device (launchd EALREADY race, mostly after an in-place update).
        /// `restartAttempted` is true once the deactivate/activate revival ran
        /// without bringing the device back — then only a reboot helps.
        case activatedNoDevice(restartAttempted: Bool)
        case error(String)

        var label: String {
            switch self {
            case .notInstalled: return "Camera extension not installed"
            case .requested: return "Installing camera extension"
            case .waitingForUser: return "Waiting for approval in System Settings"
            case .verifyingDevice: return "Checking the camera device…"
            case .enabled: return "Camera extension enabled"
            case .activatedNoDevice(let restartAttempted):
                return restartAttempted
                    ? "Extension activated, still no camera device — restart the Mac"
                    : "Extension activated, but macOS started no camera device"
            case .error(let message): return "Error: \(message)"
            }
        }
    }

    @Published var extensionState: ExtensionState = .notInstalled {
        didSet {
            report("extension: \(extensionState.label)")
            // Only a real transition may pull the setup window forward; the
            // installer re-reports the same state while approval is pending.
            // A background presence refresh sets the flag: the menu is already
            // open and showing the state, so it must not front the guide.
            refreshOnboarding(stateChanged: !suppressesOnboardingPresentation
                                  && oldValue != extensionState)
        }
    }

    /// True while `refreshDevicePresence()` writes the state, so its transition
    /// stays a menu update instead of re-fronting the setup window (#25.1).
    private var suppressesOnboardingPresentation = false
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

    /// Set once a check found a newer release; the menu turns it into a button
    /// that opens the release page (#27).
    @Published var updateAvailable: (version: String, url: URL)?
    /// Outcome of the manual "Check for updates…" item ("Up to date", error).
    /// Only that item writes here; the silent launch check stays quiet.
    @Published var updateCheckMessage: String?
    /// True while a forced check is in flight, so the menu item can say so.
    @Published var isCheckingForUpdates = false

    /// HOST:PORT from `--debug-tcp`, nil when the usbmux path is used.
    let debugTCP: String?
    /// `--headless`: no interaction expected, state changes go to stderr.
    let headless: Bool
    let activateOnStart: Bool

    private let log = Logger(subsystem: TetherCamContract.hostBundleID, category: "state")
    private var installer: ExtensionInstaller?
    private var pipeline: CameraPipeline?
    private var started = false
    /// Poll for the CMIO device after an activation (#32); at most one runs.
    private var deviceWatch: Task<Void, Never>?
    private let deviceWatcher = DevicePresenceWatcher()

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
        if activateOnStart { installExtension() } else { checkExistingExtension() }
        startPipeline()
        checkForUpdatesAtLaunch()
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
            // A transient device probe is no reason to front the guide: the
            // activation was accepted, only the device is still unconfirmed.
            extensionEnabled: extensionState == .enabled || extensionState == .verifyingDevice,
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

    /// "0.3.0" from the bundle — the marketing version alone, which is what the
    /// update check compares against a release tag.
    var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// "1.0 (7)" from the bundle; the About row and CLIENT_INFO use it.
    var versionString: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(shortVersion) (\(build))"
    }

    // MARK: - Update check (#27)

    /// Whether this launch may talk to the network at all. `--headless` and
    /// `--debug-tcp` runs exist for tests and CI: they must stay offline and
    /// deterministic, so the update check is skipped there entirely.
    var performsUpdateCheck: Bool { !headless && debugTCP == nil }

    /// User opt-out for the silent launch check (menu toggle, documented in
    /// mac-app/README.md). Default on: an unwritten key reads as true, so an
    /// existing install keeps the behaviour it had. The manual "Check for
    /// updates…" item stays available while this is off.
    var checksForUpdatesAutomatically: Bool {
        get { UserDefaults.standard.object(forKey: Self.automaticUpdateCheckKey) as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Self.automaticUpdateCheckKey)
            report("automatic update check: \(newValue ? "on" : "off")")
        }
    }

    private lazy var updateChecker = UpdateChecker(currentVersion: shortVersion)

    /// Launch path: one silent check, at most once per day (the checker owns
    /// the interval). A failure or "up to date" produces no menu text — only a
    /// found update is worth interrupting the menu for.
    func checkForUpdatesAtLaunch() {
        guard performsUpdateCheck, checksForUpdatesAutomatically else { return }
        let checker = updateChecker
        Task { [weak self] in
            guard let result = await checker.checkIfDue() else { return }
            guard let self else { return }
            self.applyUpdateResult(result, manual: false)
        }
    }

    /// Menu item "Check for updates…": bypasses the daily interval and always
    /// leaves a sentence behind, including for "up to date" and failures.
    func checkForUpdatesNow() {
        guard performsUpdateCheck, !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        updateCheckMessage = nil
        let checker = updateChecker
        Task { [weak self] in
            let result = await checker.check(force: true)
            guard let self else { return }
            self.isCheckingForUpdates = false
            self.applyUpdateResult(result, manual: true)
        }
    }

    /// Pure-ish rendering of a check result into the two published fields.
    private func applyUpdateResult(_ result: UpdateResult, manual: Bool) {
        switch result {
        case .available(let latest, let url):
            updateAvailable = (version: latest, url: url)
            if manual { updateCheckMessage = nil }
            report("update available: \(latest)")
        case .upToDate(let latest):
            updateAvailable = nil
            if manual { updateCheckMessage = "TetherCam \(shortVersion) is up to date." }
            report("update check: up to date (latest \(latest))")
        case .failed(let message):
            if manual { updateCheckMessage = "Could not check for updates." }
            report("update check failed: \(message)")
        case .skippedRateLimited:
            break
        }
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
        let previous = extensionState
        let installer = ExtensionInstaller()
        installer.onChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .activated:
                    // A completed deactivation reports .activated (the request
                    // finished), which would read as "enabled" in the menu.
                    self.cancelDeviceWatch()
                    self.extensionState = .notInstalled
                default:
                    // A canceled confirmation leaves the extension running, so
                    // `map` returns `previous` — never "not installed" (#25.5).
                    self.extensionState = Self.map(state, previous: previous)
                }
            }
        }
        self.installer = installer
        installer.deactivate()
    }

    /// Submits (or re-submits) the system extension activation request.
    func installExtension() {
        // A watch from an earlier activation would otherwise write
        // .activatedNoDevice over this in-flight request and re-front the guide.
        cancelDeviceWatch()
        let previous = extensionState
        let installer = ExtensionInstaller()
        installer.onChange = { [weak self] state in
            // OSSystemExtensionRequest was created with queue: .main, but the
            // delegate contract is not annotated, so hop explicitly.
            Task { @MainActor in
                guard let self else { return }
                // "Activated" only means macOS accepted the extension; whether
                // a camera device actually exists is a separate question (#32),
                // so .enabled is published by the watch, not here.
                if state == .activated {
                    self.extensionState = .verifyingDevice
                    self.startDeviceWatch()
                } else {
                    self.extensionState = Self.map(state, previous: previous)
                }
            }
        }
        self.installer = installer
        installer.activate()
    }

    // MARK: - Device presence (#32)

    /// Launch path without an activation request (`--no-activate`): the
    /// extension may already be `[activated enabled]` from a previous run, and
    /// still have no camera device.
    private func checkExistingExtension() {
        Task { @MainActor [weak self] in
            let listed = await Task.detached { ExtensionInstaller.queryState() }.value
            guard let self, let listed, listed.contains("enabled"),
                  !listed.contains("waiting for user") else { return }
            self.extensionState = .verifyingDevice
            self.startDeviceWatch()
        }
    }

    /// Polls `CMIOSink.isDevicePresent()` for the watcher's budget. If the
    /// device never appears, the state says so instead of claiming "enabled".
    ///
    /// - Parameter restartAttempted: true when this poll follows the
    ///   deactivate/activate revival, which changes the label to "restart the Mac".
    private func startDeviceWatch(restartAttempted: Bool = false) {
        deviceWatch?.cancel()
        let watcher = deviceWatcher
        deviceWatch = Task { @MainActor [weak self] in
            let outcome = await watcher.waitForDevice(isPresent: CMIOSink.isDevicePresent)
            guard let self, !Task.isCancelled else { return }
            switch outcome {
            case .present:
                self.extensionState = .enabled
            case .absent:
                self.extensionState = .activatedNoDevice(restartAttempted: restartAttempted)
            }
        }
    }

    /// Single probe when the menu opens: the device can vanish long after the
    /// activation (extension crash, in-place replacement), and the watch only
    /// runs once per activation. Touches nothing but the two states it knows
    /// about and never starts a 10 s watch.
    func refreshDevicePresence() {
        switch extensionState {
        case .enabled, .activatedNoDevice: break
        default: return
        }
        Task { @MainActor [weak self] in
            let present = await Task.detached { CMIOSink.isDevicePresent() }.value
            guard let self else { return }
            // Re-read the state: the probe took time, and an install request may
            // have moved on in the meantime.
            switch (self.extensionState, present) {
            case (.enabled, false):
                self.setExtensionStateFromRefresh(.activatedNoDevice(restartAttempted: false))
            case (.activatedNoDevice, true):
                self.setExtensionStateFromRefresh(.enabled)
            default:
                break
            }
        }
    }

    /// Writes a state discovered by the background probe. Same value, but the
    /// setup window stays where it is — the menu that triggered the probe is
    /// already showing the label.
    private func setExtensionStateFromRefresh(_ newState: ExtensionState) {
        suppressesOnboardingPresentation = true
        extensionState = newState
        suppressesOnboardingPresentation = false
    }

    private func cancelDeviceWatch() {
        deviceWatch?.cancel()
        deviceWatch = nil
    }

    /// Revival for `.activatedNoDevice`: deactivate, wait for the deactivation
    /// to finish, then activate again. macOS asks the user to confirm both
    /// steps. If the device is still missing afterwards, the state says that a
    /// Mac restart is the remaining option.
    func restartExtension() {
        cancelDeviceWatch()
        let previous = extensionState
        let installer = ExtensionInstaller()
        installer.onChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .activated:
                    // Deactivation finished; now bring it back.
                    self.report("extension deactivated, re-activating")
                    self.reactivateAfterRestart()
                default:
                    self.extensionState = Self.map(state, previous: previous)
                }
            }
        }
        self.installer = installer
        installer.deactivate()
    }

    private func reactivateAfterRestart() {
        let installer = ExtensionInstaller()
        installer.onChange = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .canceled:
                    // The deactivation went through, the re-activation did not.
                    self.extensionState = .notInstalled
                case .activated:
                    self.extensionState = .verifyingDevice
                    self.startDeviceWatch(restartAttempted: true)
                default:
                    self.extensionState = Self.map(state, previous: .requested)
                }
            }
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

    /// Pure mapping from the installer's request state to what the menu shows.
    ///
    /// - Parameter previous: the state before the request was submitted. A
    ///   canceled macOS confirmation changes nothing on the system, so it maps
    ///   back to `previous` instead of pretending the request finished (#25.5).
    static func map(_ state: ExtensionInstaller.State, previous: ExtensionState) -> ExtensionState {
        switch state {
        case .idle: return .notInstalled
        case .requested: return .requested
        case .needsUserApproval: return .waitingForUser
        case .activated: return .enabled
        case .willCompleteAfterReboot: return .error("restart the Mac to finish installing the camera extension")
        case .canceled: return previous
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
