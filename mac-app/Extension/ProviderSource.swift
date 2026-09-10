// ProviderSource.swift
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer

import CoreMediaIO
import Foundation
import OSLog
import TetherCamContract

let extensionLogSubsystem = TetherCamContract.extensionBundleID

/// Publishes the single TetherCam device to the CMIO system.
final class ProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: DeviceSource!
    private let log = Logger(subsystem: extensionLogSubsystem, category: "provider")

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = DeviceSource()
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            log.error("addDevice failed: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {
        log.notice("client connected: \(client.clientID) pid \(client.pid)")
    }

    func disconnect(from client: CMIOExtensionClient) {
        log.notice("client disconnected: \(client.clientID) pid \(client.pid)")
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer, .providerName]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = "Bernhard Goetzendorfer"
        }
        if properties.contains(.providerName) {
            providerProperties.name = TetherCamContract.cameraName
        }
        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
        // No writable provider properties.
    }
}
