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

    /// Decides whether the guide may open *by itself* right now.
    ///
    /// `shouldShow` alone is not enough: it stays true for as long as the
    /// extension is unapproved, so a caller that re-evaluates it on every state
    /// poll drags the window back to the front over and over, and "Done" can
    /// never take effect. This adds the two gates that make it bearable.
    ///
    /// - Parameters:
    ///   - extensionEnabled: the camera extension is installed *and* approved.
    ///   - hasCompletedSetup: the user pressed "Done" in a previous run.
    ///   - headless: `--headless`; a scripted run must never get a window.
    ///   - stateChanged: the extension state actually changed (or this is the
    ///     first evaluation of a launch). Re-reporting the same state must not
    ///     re-present the window.
    ///   - suppressedThisLaunch: the user pressed "Done" in *this* run. Holds
    ///     until the app is relaunched; the menu item still opens the guide
    ///     explicitly via `shouldShow`-independent code.
    /// - Returns: true when the guide should be presented automatically.
    public static func shouldPresentAutomatically(extensionEnabled: Bool,
                                                  hasCompletedSetup: Bool,
                                                  headless: Bool,
                                                  stateChanged: Bool,
                                                  suppressedThisLaunch: Bool) -> Bool {
        if suppressedThisLaunch { return false }
        if !stateChanged { return false }
        return shouldShow(extensionEnabled: extensionEnabled,
                          hasCompletedSetup: hasCompletedSetup,
                          headless: headless)
    }
}
