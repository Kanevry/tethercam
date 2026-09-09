// DeviceSource.swift
// The TetherCam device: one source stream (what apps see) and one sink stream
// (what the host app feeds). Mirrors the OBS camera extension design.
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Bernhard Goetzendorfer

import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation
import OSLog
import TetherCamContract

final class DeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!

    let formatDescription: CMFormatDescription
    let streamFormat: CMIOExtensionStreamFormat

    private var sourceStream: StreamSource!
    private var sinkStream: StreamSink!
    private let bufferPool: CVPixelBufferPool
    private let bufferAuxAttributes: NSDictionary

    /// All streaming state lives on this queue: client counters, the placeholder
    /// timer and the consume loop hand-over.
    private let stateQueue = DispatchQueue(label: "\(extensionLogSubsystem).device", qos: .userInteractive)
    private var sourceClientCount = 0
    private var sinkClient: CMIOExtensionClient?
    private var sinkStreaming = false
    private var consumeActive = false
    private var placeholderTimer: DispatchSourceTimer?
    private var placeholderFrame: UInt64 = 0

    private let log = Logger(subsystem: extensionLogSubsystem, category: "device")

    override init() {
        var description: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: TetherCamContract.pixelFormat,
            width: TetherCamContract.width,
            height: TetherCamContract.height,
            extensions: nil,
            formatDescriptionOut: &description)
        guard status == noErr, let description else {
            fatalError("CMVideoFormatDescriptionCreate failed: \(status)")
        }
        formatDescription = description

        let poolAttributes: NSDictionary = [
            kCVPixelBufferWidthKey: TetherCamContract.width,
            kCVPixelBufferHeightKey: TetherCamContract.height,
            kCVPixelBufferPixelFormatTypeKey: TetherCamContract.pixelFormat,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as NSDictionary,
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, poolAttributes, &pool)
        guard let pool else { fatalError("CVPixelBufferPoolCreate failed") }
        bufferPool = pool
        bufferAuxAttributes = [
            kCVPixelBufferPoolAllocationThresholdKey: TetherCamContract.sinkQueueDepth + 2,
        ]

        streamFormat = CMIOExtensionStreamFormat(
            formatDescription: description,
            maxFrameDuration: TetherCamContract.frameDuration,
            minFrameDuration: TetherCamContract.frameDuration,
            validFrameDurations: nil)

        super.init()

        guard let deviceID = UUID(uuidString: TetherCamContract.deviceUID),
              let sourceID = UUID(uuidString: TetherCamContract.sourceStreamUID),
              let sinkID = UUID(uuidString: TetherCamContract.sinkStreamUID) else {
            fatalError("TetherCamContract UIDs are not valid UUIDs")
        }
        device = CMIOExtensionDevice(
            localizedName: TetherCamContract.cameraName,
            deviceID: deviceID,
            legacyDeviceID: TetherCamContract.deviceUID,
            source: self)

        sourceStream = StreamSource(streamID: sourceID, streamFormat: streamFormat, device: self)
        sinkStream = StreamSink(streamID: sinkID, streamFormat: streamFormat, device: self)
        do {
            try device.addStream(sourceStream.stream)
            try device.addStream(sinkStream.stream)
        } catch {
            log.error("addStream failed: \(error.localizedDescription)")
        }
    }

    // MARK: CMIOExtensionDeviceSource

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            // kIOAudioDeviceTransportTypeVirtual ('virt'); the constant is not
            // exported to Swift.
            deviceProperties.transportType = 0x7669_7274
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = TetherCamContract.modelName
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        // No writable device properties.
    }

    // MARK: Stream callbacks

    func sourceStreamDidStart() {
        stateQueue.async {
            self.sourceClientCount += 1
            self.log.info("source started, clients=\(self.sourceClientCount)")
            self.refresh()
        }
    }

    func sourceStreamDidStop() {
        stateQueue.async {
            self.sourceClientCount = max(0, self.sourceClientCount - 1)
            self.log.info("source stopped, clients=\(self.sourceClientCount)")
            self.refresh()
        }
    }

    func sinkStreamDidStart(client: CMIOExtensionClient?) {
        stateQueue.async {
            self.sinkClient = client
            self.sinkStreaming = client != nil
            self.log.info("sink started, client pid \(client?.pid ?? 0)")
            self.refresh()
        }
    }

    func sinkStreamDidStop() {
        stateQueue.async {
            self.sinkStreaming = false
            self.sinkClient = nil
            self.consumeActive = false
            self.log.info("sink stopped")
            self.refresh()
        }
    }

    // MARK: Placeholder <-> forwarding hand-over (stateQueue only)

    private func refresh() {
        let wantsOutput = sourceClientCount > 0
        if wantsOutput && sinkStreaming {
            stopPlaceholder()
            if !consumeActive {
                consumeActive = true
                armConsume()
            }
        } else if wantsOutput {
            consumeActive = false
            startPlaceholder()
        } else {
            consumeActive = false
            stopPlaceholder()
        }
    }

    private func armConsume() {
        guard consumeActive, let client = sinkClient else { return }
        sinkStream.stream.consumeSampleBuffer(from: client) { [weak self] sampleBuffer, sequenceNumber, discontinuity, _, error in
            guard let self else { return }
            self.stateQueue.async {
                guard self.consumeActive else { return }
                if let sampleBuffer {
                    let hostTime = DeviceSource.hostTimeNanoseconds()
                    self.sourceStream.stream.send(sampleBuffer, discontinuity: discontinuity, hostTimeInNanoseconds: hostTime)
                    let output = CMIOExtensionScheduledOutput(sequenceNumber: sequenceNumber, hostTimeInNanoseconds: hostTime)
                    self.sinkStream.stream.notifyScheduledOutputChanged(output)
                    self.armConsume()
                } else {
                    if let error {
                        self.log.error("consumeSampleBuffer: \(error.localizedDescription)")
                    }
                    // Re-arm after a short pause so an erroring sink does not spin.
                    self.stateQueue.asyncAfter(deadline: .now() + .milliseconds(10)) { self.armConsume() }
                }
            }
        }
    }

    private func startPlaceholder() {
        guard placeholderTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: stateQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(TetherCamContract.fps), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.emitPlaceholderFrame() }
        timer.resume()
        placeholderTimer = timer
        log.info("placeholder started")
    }

    private func stopPlaceholder() {
        guard let timer = placeholderTimer else { return }
        timer.cancel()
        placeholderTimer = nil
        log.info("placeholder stopped")
    }

    /// Dark grey NV12 frame with a lighter bar sweeping across it, so a client
    /// sees a live camera even before the iPhone delivers pictures.
    private func emitPlaceholderFrame() {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault, bufferPool, bufferAuxAttributes, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let width = Int(TetherCamContract.width)
        let barWidth = 96
        let travel = width + barWidth
        let barStart = Int((placeholderFrame * 6) % UInt64(travel)) - barWidth
        let barRange = max(0, barStart) ..< min(width, barStart + barWidth)
        if let lumaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) {
            let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            let rows = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let luma = lumaBase.assumingMemoryBound(to: UInt8.self)
            for row in 0 ..< rows {
                let line = luma + row * rowBytes
                memset(line, 40, width)
                if !barRange.isEmpty {
                    memset(line + barRange.lowerBound, 90, barRange.count)
                }
            }
        }
        if let chromaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) {
            let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
            let rows = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
            memset(chromaBase, 128, rowBytes * rows)
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        placeholderFrame += 1

        let now = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: TetherCamContract.frameDuration,
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer)
        guard sampleStatus == noErr, let sampleBuffer else { return }
        sourceStream.stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: UInt64(now.seconds * Double(NSEC_PER_SEC)))
    }

    private static func hostTimeNanoseconds() -> UInt64 {
        UInt64(CMClockGetTime(CMClockGetHostTimeClock()).seconds * Double(NSEC_PER_SEC))
    }
}
