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
            Label("pushed \(state.status.pushed)  dropped \(state.status.dropped)",
                  systemImage: "arrow.right.circle")
                .foregroundStyle(.secondary)
            if let debugTCP = state.debugTCP {
                Label("Debug TCP \(debugTCP)", systemImage: "network")
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button(installTitle) { state.installExtension() }
            Button("Open Camera Extensions settings") { state.openExtensionSettings() }
            Divider()
            Button("Quit TetherCam") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 320)
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
