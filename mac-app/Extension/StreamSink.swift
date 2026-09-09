// StreamSink.swift
// The sink stream: the TetherCam host app enqueues decoded NV12 frames here and
// the device forwards them to the source stream.
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer

import CoreMedia
import CoreMediaIO
import Foundation
import OSLog
import TetherCamContract

final class StreamSink: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private let log = Logger(subsystem: extensionLogSubsystem, category: "sink")
    private unowned let device: DeviceSource
    private let streamFormat: CMIOExtensionStreamFormat
    /// The client authorized most recently; startStream() has no client
    /// parameter, so the authorization callback records it (OBS does the same).
    private var client: CMIOExtensionClient?

    init(streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: DeviceSource) {
        self.device = device
        self.streamFormat = streamFormat
        super.init()
        stream = CMIOExtensionStream(
            localizedName: "\(TetherCamContract.cameraName) Sink",
            streamID: streamID,
            direction: .sink,
            clockType: .hostTime,
            source: self)
    }

    var formats: [CMIOExtensionStreamFormat] { [streamFormat] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [
            .streamActiveFormatIndex,
            .streamFrameDuration,
            .streamSinkBufferQueueSize,
            .streamSinkBuffersRequiredForStartup,
            .streamSinkBufferUnderrunCount,
            .streamSinkEndOfData,
        ]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = TetherCamContract.frameDuration
        }
        if properties.contains(.streamSinkBufferQueueSize) {
            streamProperties.sinkBufferQueueSize = TetherCamContract.sinkQueueDepth
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            streamProperties.sinkBuffersRequiredForStartup = 1
        }
        if properties.contains(.streamSinkBufferUnderrunCount) {
            streamProperties.sinkBufferUnderrunCount = 0
        }
        if properties.contains(.streamSinkEndOfData) {
            streamProperties.sinkEndOfData = 0
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        // One format, one frame duration: nothing to change.
    }

    /// Only the TetherCam host app may feed the sink; any other process could
    /// otherwise inject frames into every app that selected "TetherCam". The
    /// source stream stays open to all clients (that is the point of a camera).
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        // Same policy as OBS's camera extension: any local client may feed
        // the sink. A signingID gate was tried on 2026-09-09 and locked the
        // host out: CMIOExtensionClient.signingID is nil for the Apple
        // Development-signed TetherCam.app on macOS 26.6. Revisit with a
        // Developer ID build (spec, open risk "sink authorization").
        log.info("sink client pid \(client.pid) signingID \(client.signingID ?? "<nil>", privacy: .public)")
        self.client = client
        return true
    }

    func startStream() throws {
        device.sinkStreamDidStart(client: client)
    }

    func stopStream() throws {
        client = nil
        device.sinkStreamDidStop()
    }
}
