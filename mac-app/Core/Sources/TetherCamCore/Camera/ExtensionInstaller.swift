// SPDX-License-Identifier: MIT
// ExtensionInstaller.swift
// TetherCam for macOS: installs / removes the Camera Extension via the
// SystemExtensions framework and reports what `systemextensionsctl` knows.

import AppKit
import Foundation
import SystemExtensions
import TetherCamContract

/// Drives `OSSystemExtensionRequest` for the TetherCam Camera Extension.
/// Create one instance, set `onChange`, call `activate()`; the delegate
/// callbacks arrive on the main queue.
public final class ExtensionInstaller: NSObject, OSSystemExtensionRequestDelegate {
    public enum State: Equatable {
        case idle
        case requested
        /// macOS wants the user to allow the extension in System Settings.
        case needsUserApproval
        case activated
        case willCompleteAfterReboot
        case failed(String)
    }

    /// Deep link to Login Items & Extensions, where the user approves
    /// (or re-enables) the camera extension.
    public static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

    public private(set) var state: State = .idle {
        didSet { onChange(state) }
    }
    public var onChange: (State) -> Void = { _ in }

    public override init() {}

    // MARK: - Requests

    /// Submits an activation request; a fresh install ends in
    /// `.needsUserApproval`, an update or an already-approved extension in
    /// `.activated`.
    public func activate() {
        submit(OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: TetherCamContract.extensionBundleID, queue: .main))
    }

    /// Submits a deactivation request (the user must still confirm once).
    public func deactivate() {
        submit(OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: TetherCamContract.extensionBundleID, queue: .main))
    }

    private func submit(_ request: OSSystemExtensionRequest) {
        request.delegate = self
        state = .requested
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    public static func openSystemSettings() {
        NSWorkspace.shared.open(systemSettingsURL)
    }

    // MARK: - OSSystemExtensionRequestDelegate

    public func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    public func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        state = .needsUserApproval
    }

    public func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed: state = .activated
        case .willCompleteAfterReboot: state = .willCompleteAfterReboot
        @unknown default: state = .failed("unknown result \(result.rawValue)")
        }
    }

    public func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        state = .failed(Self.message(for: error))
    }

    /// Human-readable failure text; the parent-bundle case is the one users
    /// hit most (app launched from Downloads or a DMG).
    static func message(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == OSSystemExtensionErrorDomain,
              let code = OSSystemExtensionError.Code(rawValue: nsError.code) else {
            return "\(error.localizedDescription) (\(nsError.domain) \(nsError.code))"
        }
        switch code {
        case .unsupportedParentBundleLocation:
            return "TetherCam.app must be in /Applications"
        case .authorizationRequired:
            return "The extension needs your approval in System Settings > Login Items & Extensions"
        case .extensionNotFound:
            return "The camera extension is missing from the app bundle"
        case .codeSignatureInvalid:
            return "The camera extension's code signature is invalid"
        case .validationFailed:
            return "macOS rejected the camera extension (validation failed)"
        default:
            return "\(error.localizedDescription) (code \(nsError.code))"
        }
    }

    // MARK: - systemextensionsctl

    /// Extracts the bracketed state of the TetherCam extension from
    /// `systemextensionsctl list` output, e.g. "activated enabled" or
    /// "activated waiting for user". Nil when the extension is not listed.
    ///
    /// Line format (tab separated):
    /// `*\t\tTEAMID\tbundle.id (ver/build)\tName\t[state]`
    public static func parseState(from text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            guard line.contains(TetherCamContract.extensionBundleID),
                  let open = line.lastIndex(of: "["),
                  let close = line[open...].firstIndex(of: "]"),
                  close > open else { continue }
            return String(line[line.index(after: open)..<close])
        }
        return nil
    }

    /// Runs `systemextensionsctl list` and parses the TetherCam line.
    /// Nil when the tool is unavailable, fails, or does not list the extension.
    public static func queryState() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/systemextensionsctl")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        return parseState(from: text)
    }
}
