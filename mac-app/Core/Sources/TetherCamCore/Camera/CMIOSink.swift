// SPDX-License-Identifier: MIT
// CMIOSink.swift
// TetherCam for macOS: pushes decoded NV12 frames into the SINK stream of the
// TetherCam Camera Extension through the CoreMediaIO hardware API. The
// extension mirrors every sample buffer it dequeues from the sink onto its
// SOURCE stream, which is what Zoom, FaceTime & co. see as "TetherCam".
//
// API sequence (CMIOObject property enumeration -> CMIOStreamCopyBufferQueue
// -> CMIODeviceStartStream -> CMSimpleQueueEnqueue) follows the public
// CoreMediaIO contract; the code is written fresh and MIT-licensed.

import CoreMedia
import CoreMediaIO
import CoreVideo
import Foundation
import TetherCamContract

/// Errors raised while attaching to the Camera Extension's sink stream.
public enum CMIOSinkError: Error, Equatable {
    /// No CMIO device advertises `TetherCamContract.deviceUID`; the system
    /// extension is not installed, not approved, or not running.
    case deviceNotFound
    /// The device exists but exposes no stream that accepts frames.
    case noSinkStream
    /// A CoreMediaIO call failed; `String` names the call.
    case osStatus(Int32, String)
}

/// Host-side bridge into the Camera Extension's sink stream.
///
/// `push(_:ptsUs:)` is safe to call from any thread (VideoToolbox decode
/// callbacks included); `connect()` / `disconnect()` serialize against it.
public final class CMIOSink {
    /// Direction value of `kCMIOStreamPropertyDirection` for a stream the
    /// client writes INTO. CMIOHardwareStream.h says "0 = output stream,
    /// 1 = input stream" and means it from the APP's point of view: a camera's
    /// capture stream (extension direction .source) reports 1, the extension's
    /// .sink stream reports 0. Measured on macOS 26.6 against this extension:
    /// stream[0] (.source) -> 1, stream[1] (.sink) -> 0. Picking 1 started the
    /// SOURCE stream from the host and the sink never consumed a frame.
    static let sinkDirection: UInt32 = 0

    private let lock = NSLock()
    private var deviceID: CMIOObjectID = 0
    private var streamID: CMIOStreamID = 0
    private var queue: CMSimpleQueue?
    private var formatDescription: CMVideoFormatDescription?
    private var pushed: UInt64 = 0
    private var dropped: UInt64 = 0

    public init() {}

    deinit { disconnect() }

    /// Frames handed to the extension since `connect()`.
    public var pushedFrames: UInt64 { lock.withLock { pushed } }
    /// Frames discarded because the sink queue was full.
    public var droppedFrames: UInt64 { lock.withLock { dropped } }
    public var isConnected: Bool { lock.withLock { queue != nil } }

    // MARK: - Lifecycle

    /// Locates the TetherCam device, selects its sink stream, copies the
    /// stream's buffer queue and starts the stream.
    public func connect() throws {
        lock.lock()
        defer { lock.unlock() }
        guard queue == nil else { return }

        guard let device = try Self.findDevice() else { throw CMIOSinkError.deviceNotFound }
        let streams = try Self.streamIDs(of: device)
        guard let sink = Self.selectSinkStream(streams) else { throw CMIOSinkError.noSinkStream }

        var copied: Unmanaged<CMSimpleQueue>?
        // The altered proc must be non-nil: with nil, CMIOStreamCopyBufferQueue
        // returns noErr and NO queue (measured on macOS 26.6, both stream
        // directions). The callback itself is a no-op; back-pressure is handled
        // by count/capacity in push().
        let copyStatus = CMIOStreamCopyBufferQueue(sink, { _, _, _ in }, nil, &copied)
        guard copyStatus == noErr, let copied else {
            throw CMIOSinkError.osStatus(copyStatus, "CMIOStreamCopyBufferQueue")
        }
        // The header states the client owns the returned queue: take the +1.
        let q = copied.takeRetainedValue()

        let startStatus = CMIODeviceStartStream(device, sink)
        guard startStatus == noErr else {
            throw CMIOSinkError.osStatus(startStatus, "CMIODeviceStartStream")
        }

        deviceID = device
        streamID = sink
        queue = q
        pushed = 0
        dropped = 0
    }

    /// Stops the stream and drops the queue reference. Idempotent.
    public func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        guard queue != nil else { return }
        CMIODeviceStopStream(deviceID, streamID)
        queue = nil   // CMSimpleQueue is CF-bridged; ARC releases it here.
        formatDescription = nil
        deviceID = 0
        streamID = 0
    }

    // MARK: - Frames

    /// Wraps `pixelBuffer` in a sample buffer and enqueues it on the sink.
    /// Frames arriving while the queue is full are dropped, never blocked on.
    /// No-op when not connected.
    public func push(_ pixelBuffer: CVPixelBuffer, ptsUs: Int64) {
        lock.lock()
        defer { lock.unlock() }
        guard let queue else { return }

        if CMSimpleQueueGetCount(queue) >= CMSimpleQueueGetCapacity(queue) {
            dropped += 1
            return
        }

        let sample: CMSampleBuffer
        do {
            sample = try Self.makeSampleBuffer(from: pixelBuffer, ptsUs: ptsUs, formatDescription: &formatDescription)
        } catch {
            dropped += 1
            return
        }

        // The extension (consumer) takes over the +1 reference on dequeue.
        let retained = Unmanaged.passRetained(sample)
        let status = CMSimpleQueueEnqueue(queue, element: retained.toOpaque())
        if status == noErr {
            pushed += 1
        } else {
            retained.release()
            dropped += 1
        }
    }

    /// Timing for one published frame: duration 1/fps, pts in microseconds,
    /// no decode timestamp (frames are already in presentation order).
    public static func timing(ptsUs: Int64) -> CMSampleTimingInfo {
        CMSampleTimingInfo(
            duration: TetherCamContract.frameDuration,
            presentationTimeStamp: CMTime(value: ptsUs, timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
    }

    /// Builds a ready-to-consume sample buffer around `pixelBuffer`.
    /// `formatDescription` is reused while it still matches the buffer's
    /// (width, height, pixel format) and rebuilt otherwise.
    public static func makeSampleBuffer(
        from pixelBuffer: CVPixelBuffer,
        ptsUs: Int64,
        formatDescription: inout CMVideoFormatDescription?
    ) throws -> CMSampleBuffer {
        if let fd = formatDescription, !CMVideoFormatDescriptionMatchesImageBuffer(fd, imageBuffer: pixelBuffer) {
            formatDescription = nil
        }
        if formatDescription == nil {
            var created: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &created)
            guard status == noErr, let created else {
                throw CMIOSinkError.osStatus(status, "CMVideoFormatDescriptionCreateForImageBuffer")
            }
            formatDescription = created
        }

        var timingInfo = timing(ptsUs: ptsUs)
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription!,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sample)
        guard status == noErr, let sample else {
            throw CMIOSinkError.osStatus(status, "CMSampleBufferCreateReadyWithImageBuffer")
        }
        return sample
    }

    // MARK: - Device discovery

    /// True when a CMIO device with `TetherCamContract.deviceUID` is
    /// enumerable, i.e. the extension is installed, approved and running.
    public static func isDevicePresent() -> Bool {
        (try? findDevice()) != nil
    }

    private static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    /// Reads an array-valued property (`[CMIOObjectID]`, `[CMIOStreamID]`).
    private static func objectIDs(of object: CMIOObjectID, selector: Int) throws -> [CMIOObjectID] {
        var addr = address(selector)
        var size: UInt32 = 0
        let sizeStatus = CMIOObjectGetPropertyDataSize(object, &addr, 0, nil, &size)
        guard sizeStatus == noErr else { throw CMIOSinkError.osStatus(sizeStatus, "CMIOObjectGetPropertyDataSize") }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        guard count > 0 else { return [] }

        var ids = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        let dataStatus = ids.withUnsafeMutableBytes { buf in
            CMIOObjectGetPropertyData(object, &addr, 0, nil, size, &used, buf.baseAddress!)
        }
        guard dataStatus == noErr else { throw CMIOSinkError.osStatus(dataStatus, "CMIOObjectGetPropertyData") }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    /// Reads a CFString-valued property; nil when the object does not answer.
    private static func string(of object: CMIOObjectID, selector: Int) -> String? {
        var addr = address(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr,
              Int(size) >= MemoryLayout<Unmanaged<CFString>?>.size else { return nil }
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &value) { ptr in
            CMIOObjectGetPropertyData(object, &addr, 0, nil, size, &used, ptr)
        }
        guard status == noErr, let value else { return nil }
        // The property hands out a +1 reference (the caller owns it).
        return value.takeRetainedValue() as String
    }

    private static func uint32(of object: CMIOObjectID, selector: Int) -> UInt32? {
        var addr = address(selector)
        var value: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            object, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value)
        return status == noErr ? value : nil
    }

    private static func findDevice() throws -> CMIOObjectID? {
        let devices = try objectIDs(of: CMIOObjectID(kCMIOObjectSystemObject), selector: kCMIOHardwarePropertyDevices)
        return devices.first { string(of: $0, selector: kCMIODevicePropertyDeviceUID) == TetherCamContract.deviceUID }
    }

    private static func streamIDs(of device: CMIOObjectID) throws -> [CMIOStreamID] {
        try objectIDs(of: device, selector: kCMIODevicePropertyStreams)
    }

    /// Picks the stream reporting input direction (client writes into it);
    /// falls back to the second stream (extension order: source first, sink
    /// second) when the direction property is unreadable on any stream. The
    /// C API exposes no per-stream UID, so `sinkStreamUID` cannot be matched here.
    static func selectSinkStream(_ streams: [CMIOStreamID]) -> CMIOStreamID? {
        let directions = streams.map { uint32(of: $0, selector: kCMIOStreamPropertyDirection) }
        if directions.allSatisfy({ $0 != nil }) {
            if let i = directions.firstIndex(of: sinkDirection) { return streams[i] }
            return nil
        }
        return streams.count >= 2 ? streams[1] : nil
    }
}
