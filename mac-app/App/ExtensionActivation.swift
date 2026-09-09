// ExtensionActivation.swift
// Minimal in-app activation of the camera system extension. The richer
// installer lives in TetherCamCore (ExtensionInstaller); W3 consolidates both.
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer

import Foundation
import OSLog
import SystemExtensions
import TetherCamContract

final class ExtensionActivation: NSObject, OSSystemExtensionRequestDelegate {
    typealias StateHandler = @MainActor (AppState.ExtensionState) -> Void

    private let log = Logger(subsystem: TetherCamContract.hostBundleID, category: "sysext")
    private let onState: StateHandler

    init(onState: @escaping StateHandler) {
        self.onState = onState
    }

    func activate() {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: TetherCamContract.extensionBundleID,
            queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        log.info("submitted activation request for \(TetherCamContract.extensionBundleID)")
    }

    // MARK: OSSystemExtensionRequestDelegate

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        log.info("replacing extension \(existing.bundleShortVersion) (\(existing.bundleVersion)) with \(ext.bundleShortVersion) (\(ext.bundleVersion))")
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        log.info("activation needs user approval in System Settings")
        publish(.waitingForUser)
    }

    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            log.info("activation completed")
            publish(.enabled)
        case .willCompleteAfterReboot:
            log.info("activation completes after reboot")
            publish(.error("restart the Mac to finish installing the camera extension"))
        @unknown default:
            log.info("activation finished with unknown result \(result.rawValue)")
            publish(.error("unknown activation result \(result.rawValue)"))
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let nsError = error as NSError
        log.error("activation failed: \(nsError.domain) \(nsError.code) \(nsError.localizedDescription)")
        publish(.error(Self.message(for: nsError)))
    }

    /// Maps the common OSSystemExtensionError codes to a sentence the user can act on.
    static func message(for error: NSError) -> String {
        guard error.domain == OSSystemExtensionErrorDomain,
              let code = OSSystemExtensionError.Code(rawValue: error.code) else {
            return error.localizedDescription
        }
        switch code {
        case .unsupportedParentBundleLocation:
            return "move TetherCam.app to /Applications and start it again"
        case .extensionNotFound, .extensionMissingIdentifier:
            return "camera extension missing from the app bundle"
        case .codeSignatureInvalid, .validationFailed:
            return "code signature of the camera extension is invalid"
        case .authorizationRequired, .requestCanceled:
            return "approval was cancelled, use System Settings to allow the extension"
        case .forbiddenBySystemPolicy:
            return "system policy forbids the camera extension"
        case .requestSuperseded:
            return "a newer activation request replaced this one"
        default:
            return error.localizedDescription
        }
    }

    private func publish(_ state: AppState.ExtensionState) {
        Task { @MainActor in self.onState(state) }
    }
}
