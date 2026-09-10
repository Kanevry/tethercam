// MenuBarView.swift
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer

import SwiftUI
import TetherCamCore

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(state.extensionState.label, systemImage: extensionSymbol)
            Label(cameraLabel, systemImage: "video")
            Label(linkLabel, systemImage: "iphone")
            Label("\(state.status.resolution)  \(String(format: "%.1f", state.status.fps)) fps",
                  systemImage: "rectangle.dashed")
            if let flowLabel {
                Label(flowLabel, systemImage: flowSymbol)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.showsCounters {
                // Raw counters are diagnostics, not a health indicator: with no
                // app reading the camera `dropped` climbs by one per frame by
                // design (see PipelineStatus.noConsumer). Only --debug-tcp /
                // --headless runs show them.
                Label("received \(state.status.received)  pushed \(state.status.pushed)  "
                      + "dropped \(state.status.dropped)  queue \(state.status.sinkQueueCapacity)",
                      systemImage: "arrow.right.circle")
                    .foregroundStyle(.secondary)
            }
            if let debugTCP = state.debugTCP {
                Label("Debug TCP \(debugTCP)", systemImage: "network")
                    .foregroundStyle(.secondary)
            }
            if case .activatedNoDevice(let restartAttempted) = state.extensionState {
                // #32: macOS says "activated" while no camera device exists.
                // Name it and offer the deactivate/activate revival.
                Text(restartAttempted ? OnboardingStrings.noDeviceAfterRestartBody
                                      : OnboardingStrings.noDeviceBody)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .activatedNoDevice = state.extensionState {
                // The one maintenance action that belongs next to the status:
                // in this state it is what the user has to do right now.
                Button(OnboardingStrings.restartExtensionButton) { state.restartExtension() }
            }
            Divider()
            Button(OnboardingStrings.menuItem) { state.showOnboarding() }
            if let update = state.updateAvailable {
                // #27: the only update mechanism the app has — it points at the
                // release page, downloading and installing stays manual.
                Button("Update available: \(Self.displayVersion(update.version))") {
                    NSWorkspace.shared.open(update.url)
                }
            }
            Divider()
            // #33: maintenance actions move off the top level — the overview
            // shows status plus the two things a user opens daily.
            Menu("Camera extension") {
                if case .activatedNoDevice = state.extensionState {
                    Button(OnboardingStrings.restartExtensionButton) { state.restartExtension() }
                }
                Button(installTitle) { state.installExtension() }
                Button("Open Camera Extensions settings") { state.openExtensionSettings() }
                Divider()
                Button("Remove camera extension…") { confirmRemoveExtension() }
            }
            .fixedSize()
            Menu("Settings") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }))
                if let error = state.launchAtLoginError {
                    Text(error)
                }
                if state.performsUpdateCheck {
                    // Opt-out for the silent daily check only — the manual
                    // check below keeps working while this is off.
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { state.checksForUpdatesAutomatically },
                        set: { state.checksForUpdatesAutomatically = $0 }))
                    Button(state.isCheckingForUpdates ? "Checking for updates…" : "Check for updates now") {
                        state.checkForUpdatesNow()
                    }
                    .disabled(state.isCheckingForUpdates)
                    if let message = state.updateCheckMessage {
                        Text(message)
                    }
                }
            }
            .fixedSize()
            Divider()
            Text("TetherCam \(state.versionString)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Quit TetherCam") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 320)
        // The device can disappear while the app runs (#32); the activation
        // watch only probes once, so re-probe whenever the menu is opened.
        .onAppear { state.refreshDevicePresence() }
    }

    /// Release tags carry a leading "v" ("v0.4.0"); the menu shows the plain
    /// number so it reads like the version row right below it.
    static func displayVersion(_ tag: String) -> String {
        (tag.hasPrefix("v") || tag.hasPrefix("V")) ? String(tag.dropFirst()) : tag
    }

    /// Deactivating the extension kills the virtual camera for every app, so it
    /// asks first. macOS then requires its own confirmation on top.
    private func confirmRemoveExtension() {
        let alert = NSAlert()
        alert.messageText = "Remove the TetherCam camera extension?"
        alert.informativeText = "The camera \"TetherCam\" disappears from every app until you "
            + "activate the extension again. macOS asks you to confirm the removal. "
            + "Afterwards you can drag TetherCam.app to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        state.removeExtension()
    }

    /// The one sentence that replaces the drop counter: idle, flowing, or nothing.
    private var flowLabel: String? {
        if state.status.noConsumer {
            return "Camera ready — no app is reading it yet. Pick \"TetherCam\" in Zoom, Teams, Meet or FaceTime."
        }
        if state.status.link == .streaming, state.status.camera == .ready, state.status.pushed > 0 {
            return "Sending frames to the camera"
        }
        return nil
    }

    private var flowSymbol: String {
        state.status.noConsumer ? "pause.circle" : "arrow.right.circle"
    }

    private var linkLabel: String {
        switch state.status.link {
        case .noDevice: return "No iPhone connected"
        case .waiting: return "Waiting for the TetherCam app on the iPhone"
        case .starting: return "Connecting to iPhone"
        case .streaming: return "Streaming from iPhone"
        case .incompatible: return "iPhone app version incompatible"
        case .busy: return "iPhone is busy with another receiver"
        }
    }

    private var cameraLabel: String {
        switch state.status.camera {
        case .extensionMissing: return "Camera: extension not active"
        case .waitingForUser: return "Camera: waiting for approval"
        case .ready: return "Camera: ready"
        case .error(let message): return "Camera: \(message)"
        }
    }

    private var extensionSymbol: String {
        switch state.extensionState {
        case .enabled: return "checkmark.circle"
        case .waitingForUser, .requested, .verifyingDevice: return "hourglass"
        case .notInstalled: return "circle"
        case .activatedNoDevice, .error: return "exclamationmark.triangle"
        }
    }

    private var installTitle: String {
        switch state.extensionState {
        case .waitingForUser, .requested, .verifyingDevice: return "Retry camera extension activation"
        case .enabled, .activatedNoDevice: return "Reinstall camera extension"
        case .notInstalled, .error: return "Activate camera extension"
        }
    }
}
