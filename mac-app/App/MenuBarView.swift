// MenuBarView.swift
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer

import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(state.extensionState.label, systemImage: extensionSymbol)
            Label(state.linkState, systemImage: "iphone")
            Label(state.resolution, systemImage: "rectangle.dashed")
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
        .frame(width: 300)
    }

    private var extensionSymbol: String {
        switch state.extensionState {
        case .enabled: return "checkmark.circle"
        case .waitingForUser: return "hourglass"
        case .notInstalled: return "circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var installTitle: String {
        switch state.extensionState {
        case .waitingForUser: return "Approve camera extension"
        case .enabled: return "Reinstall camera extension"
        case .notInstalled, .error: return "Install camera extension"
        }
    }
}
