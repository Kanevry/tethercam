// SPDX-License-Identifier: MIT
// CameraStatus.swift
// TetherCam for macOS: one-shot health probe of the Camera Extension that the
// menu bar UI renders as "install", "approve in Settings" or "ready".

import Foundation

public enum CameraStatus: Equatable {
    /// `systemextensionsctl` does not list the extension: never activated.
    case extensionMissing
    /// Activated but blocked until the user allows it in System Settings.
    case waitingForUser
    /// Enabled and the CMIO device is enumerable: frames can flow.
    case ready
    /// Any other listed state, or enabled without a visible device.
    case error(String)

    /// Combines the `systemextensionsctl` state with CMIO device presence.
    public static func probe() -> CameraStatus {
        interpret(state: ExtensionInstaller.queryState(), devicePresent: CMIOSink.isDevicePresent())
    }

    /// Pure mapping so the decision table is testable without the tools.
    static func interpret(state: String?, devicePresent: Bool) -> CameraStatus {
        guard let state else { return .extensionMissing }
        if state.contains("waiting for user") { return .waitingForUser }
        if state.contains("enabled") {
            return devicePresent ? .ready : .error("extension enabled but the TetherCam camera device is not visible")
        }
        return .error("extension state: \(state)")
    }
}
