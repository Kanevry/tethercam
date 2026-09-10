// SPDX-License-Identifier: MIT
// OnboardingPolicy.swift
// TetherCam for macOS: the one rule that decides whether the setup guide opens
// by itself. Pure, so it can be tested without a window server.

import Foundation

/// Decides whether the first-run / setup window opens automatically.
///
/// Lives in Core (not in `AppState`) so the rule is unit-testable: it is pure
/// input → Bool with no AppKit, no UserDefaults and no window.
public enum OnboardingPolicy {

    /// - Parameters:
    ///   - extensionEnabled: the camera extension is installed *and* approved.
    ///   - hasCompletedSetup: the user pressed "Done" in a previous run
    ///     (`UserDefaults` flag).
    ///   - headless: `--headless`; a scripted run must never get a window.
    /// - Returns: true when the guide should be shown automatically.
    public static func shouldShow(extensionEnabled: Bool,
                                  hasCompletedSetup: Bool,
                                  headless: Bool) -> Bool {
        if headless { return false }
        // Not approved means the app cannot work at all — the guide explains why,
        // even for a user who dismissed it once.
        if !extensionEnabled { return true }
        return !hasCompletedSetup
    }
}
