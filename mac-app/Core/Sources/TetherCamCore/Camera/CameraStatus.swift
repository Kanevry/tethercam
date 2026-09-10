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

/// Waits for the CMIO camera device to appear after an activation.
///
/// Why this exists: when the camera extension is replaced in place (an app
/// update), launchd sometimes rejects the new CMIOExtension job with EALREADY
/// while the old job of the same label is still being torn down, and
/// `registerassistantservice` never resubmits it. `systemextensionsctl` then
/// reports the new build as `[activated enabled]` while no extension process
/// runs and no camera device exists. Polling for the device is the only way the
/// app can tell that state apart from a healthy activation.
///
/// The poll loop is separated from the clock and from CMIO so it can be tested:
/// `wait(isPresent:sleep:)` is pure, `waitForDevice(isPresent:)` is the async
/// production driver on top of the same `attempts` budget.
public struct DevicePresenceWatcher: Sendable {
    public enum Outcome: Equatable {
        /// The device showed up within the budget.
        case present
        /// The budget elapsed without the device ever appearing.
        case absent
    }

    /// Seconds between two probes.
    public let pollInterval: TimeInterval
    /// Total seconds the device gets to appear.
    public let budget: TimeInterval

    /// - Parameters:
    ///   - pollInterval: seconds between probes, clamped to at least 10 ms.
    ///   - budget: total seconds before the device counts as absent.
    public init(pollInterval: TimeInterval = 1, budget: TimeInterval = 10) {
        self.pollInterval = Swift.max(0.01, pollInterval)
        self.budget = Swift.max(0, budget)
    }

    /// Number of probes: one immediately, then one per poll interval in budget.
    public var attempts: Int {
        1 + Int((budget / Swift.max(0.01, pollInterval)).rounded(.down))
    }

    /// Pure poll loop: probes `isPresent` up to `attempts` times and calls
    /// `sleep` between two probes (never after the last one).
    public func wait(isPresent: () -> Bool, sleep: (TimeInterval) -> Void) -> Outcome {
        for attempt in 0..<attempts {
            if isPresent() { return .present }
            if attempt < attempts - 1 { sleep(pollInterval) }
        }
        return .absent
    }

    /// Production driver: same budget, `Task.sleep` as the clock. Cancellation
    /// ends the wait with `.absent`; callers check `Task.isCancelled` themselves.
    public func waitForDevice(isPresent: () -> Bool = CMIOSink.isDevicePresent) async -> Outcome {
        for attempt in 0..<attempts {
            if isPresent() { return .present }
            guard attempt < attempts - 1 else { break }
            do {
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            } catch {
                return .absent
            }
        }
        return .absent
    }
}
