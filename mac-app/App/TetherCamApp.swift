// TetherCamApp.swift
// TetherCam for macOS: menu bar host for the iPhone USB camera.
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer

import SwiftUI

@main
struct TetherCamApp: App {
    @ObservedObject private var state = AppState.shared

    init() {
        // The menu content only exists while the popover is open, so the
        // pipeline starts from here instead of from an onAppear.
        AppState.shared.start()
    }

    var body: some Scene {
        // LSUIElement is set in Info.plist: no Dock icon, no main window. In
        // --headless mode the menu bar item still exists but nobody needs it;
        // the state also goes to stderr.
        MenuBarExtra("TetherCam", systemImage: "camera") {
            MenuBarView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}
