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
            Divider()
            Button(installTitle) { state.installExtension() }
            Button("Open Camera Extensions settings") { state.openExtensionSettings() }
            Button(OnboardingStrings.menuItem) { state.showOnboarding() }
            Divider()
            Toggle("Launch at Login", isOn: Binding(
                get: { state.launchAtLogin },
                set: { state.setLaunchAtLogin($0) }))
                .toggleStyle(.checkbox)
            if let error = state.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Remove camera extension…") { confirmRemoveExtension() }
            Divider()
            Text("TetherCam \(state.versionString)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Quit TetherCam") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 320)
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
        case .waitingForUser, .requested: return "hourglass"
        case .notInstalled: return "circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var installTitle: String {
        switch state.extensionState {
        case .waitingForUser, .requested: return "Retry camera extension activation"
        case .enabled: return "Reinstall camera extension"
        case .notInstalled, .error: return "Activate camera extension"
        }
    }
}
