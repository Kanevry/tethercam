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
    /// pid of the client whose authorization was already logged (see
    /// `authorizedToStartStream`), so a restart does not spam the log.
    private var loggedClientPID: pid_t?

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
        // Same policy as OBS's camera extension: any local client may feed the
        // sink. A signingID gate was measured twice and stays impossible here:
        // 2026-09-09 with an Apple Development build and 2026-09-10 with a
        // Developer ID build (macOS 26.6.2/25G83, simulated *and* live iPhone
        // stream) CMIOExtensionClient.signingID carries no usable value, so a
        // gate would lock out the host itself. See the dated addendum in
        // docs/superpowers/specs/2026-09-09-virtual-camera-cmio.md (#28).
        //
        // One line per client, not per start: the callback fires again on every
        // stream start, and the value only ever changes with the client.
        if loggedClientPID != client.pid {
            loggedClientPID = client.pid
            let signingID = client.signingID
            // `present` is logged separately because the unified log renders an
            // absent %{public}s as "unknown" — indistinguishable from a literal
            // fallback string, which cost an hour on 2026-09-10.
            log.notice("""
                sink client pid \(client.pid, privacy: .public) \
                signingID present \(signingID != nil, privacy: .public) \
                value '\(signingID ?? "", privacy: .public)'
                """)
        }
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
