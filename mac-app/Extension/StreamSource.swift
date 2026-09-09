// StreamSource.swift
// The source stream: what Zoom, FaceTime, ffmpeg etc. read from.
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer

import CoreMedia
import CoreMediaIO
import Foundation
import TetherCamContract

final class StreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private unowned let device: DeviceSource
    private let streamFormat: CMIOExtensionStreamFormat

    init(streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: DeviceSource) {
        self.device = device
        self.streamFormat = streamFormat
        super.init()
        stream = CMIOExtensionStream(
            localizedName: "\(TetherCamContract.cameraName) Video",
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [streamFormat] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = TetherCamContract.frameDuration
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        // One format, one frame duration: nothing to change.
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        true
    }

    func startStream() throws {
        device.sourceStreamDidStart()
    }

    func stopStream() throws {
        device.sourceStreamDidStop()
    }
}
