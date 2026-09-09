// SPDX-License-Identifier: MIT
// HevcDecoder.swift
// TetherCam for macOS: VideoToolbox HEVC decoder for the IUCM VIDEO payload
// (PROTOCOL.md 4.6: 4-byte big-endian length-prefixed VCL NALs, parameter sets
// only in the hvcC record from CONFIG).

import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

public enum HevcDecoderError: Error, CustomStringConvertible {
    case formatDescription(OSStatus)
    case sessionCreate(OSStatus)

    public var description: String {
        switch self {
        case .formatDescription(let s): return "CMVideoFormatDescriptionCreate failed: \(s)"
        case .sessionCreate(let s): return "VTDecompressionSessionCreate failed: \(s)"
        }
    }
}

/// Result of one `decode` call.
public enum HevcDecodeResult: Equatable, Sendable {
    /// Submitted to VideoToolbox; `onFrame` has fired (or the output callback
    /// reported an error) by the time `decode` returns, see the class doc.
    case accepted
    /// Dropped: no keyframe since (re)creation yet, so this frame has no reference.
    case droppedAwaitingKeyframe
    /// VideoToolbox refused the frame.
    case failed(OSStatus)
}

/// One decoder per CONFIG. Not thread-safe: call `decode` and `close` from one
/// thread (the receiver thread).
///
/// Threading of the output callback: `decode` passes only `._1xRealTimePlayback`
/// and never `._EnableAsynchronousDecompression`, so
/// VideoToolbox runs the output callback synchronously inside
/// `VTDecompressionSessionDecodeFrame`, on the calling (receiver) thread; the
/// frame has been delivered when `decode` returns. Should asynchronous
/// decompression ever be enabled, the callback would move to a VideoToolbox
/// thread: `onFrame` consumers then need their own synchronisation and the
/// error bookkeeping (already under `lock`) would trigger the rebuild on the
/// next `decode` call instead of the current one.
public final class HevcDecoder {

    /// Decoded frame (NV12, IOSurface-backed) and its pts in microseconds. The
    /// buffer is retained only for the duration of the callback.
    public var onFrame: ((CVPixelBuffer, Int64) -> Void)?

    public let width: Int
    public let height: Int
    /// Decode errors since init (never reset; for telemetry): submission
    /// failures plus errors reported through the output callback.
    public var totalErrors: Int { lock.withLock { totalErrorCount } }

    /// Consecutive decode failures (submission or output callback) that
    /// trigger a session rebuild.
    public static let maxConsecutiveErrors = 3

    private let format: CMVideoFormatDescription
    private var session: VTDecompressionSession?
    /// Guards the error counters, which the output callback also touches.
    private let lock = NSLock()
    private var totalErrorCount = 0
    private var consecutiveErrors = 0
    private var needKeyframe = true

    public init(hvcC: Data, width: Int, height: Int) throws {
        self.width = width
        self.height = height
        let atoms: [CFString: Any] = ["hvcC" as CFString: hvcC as CFData]
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: atoms,
        ]
        var fmt: CMVideoFormatDescription?
        let st = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                                codecType: kCMVideoCodecType_HEVC,
                                                width: Int32(width), height: Int32(height),
                                                extensions: extensions as CFDictionary,
                                                formatDescriptionOut: &fmt)
        guard st == noErr, let fmt else { throw HevcDecoderError.formatDescription(st) }
        format = fmt
        try createSession()
    }

    deinit {
        close()
    }

    private func createSession() throws {
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var s: VTDecompressionSession?
        let st = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                              formatDescription: format,
                                              decoderSpecification: nil,
                                              imageBufferAttributes: attrs as CFDictionary,
                                              outputCallback: nil,
                                              decompressionSessionOut: &s)
        guard st == noErr, let s else { throw HevcDecoderError.sessionCreate(st) }
        session = s
        lock.withLock { consecutiveErrors = 0 }
        needKeyframe = true
    }

    /// True while frames are being dropped for lack of a keyframe.
    public var isWaitingForKeyframe: Bool { needKeyframe }

    /// Drains and invalidates the session. Idempotent.
    public func close() {
        guard let s = session else { return }
        VTDecompressionSessionWaitForAsynchronousFrames(s)
        VTDecompressionSessionInvalidate(s)
        session = nil
    }

    /// Wraps the length-prefixed NALs in a sample buffer and submits them.
    @discardableResult
    public func decode(nalData: Data, ptsUs: Int64, keyframe: Bool) -> HevcDecodeResult {
        if needKeyframe {
            guard keyframe else { return .droppedAwaitingKeyframe }
            needKeyframe = false
        }
        guard let s = session else { return .failed(kVTInvalidSessionErr) }

        var block: CMBlockBuffer?
        let len = nalData.count
        var st = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                    blockLength: len, blockAllocator: kCFAllocatorDefault,
                                                    customBlockSource: nil, offsetToData: 0,
                                                    dataLength: len,
                                                    flags: kCMBlockBufferAssureMemoryNowFlag,
                                                    blockBufferOut: &block)
        guard st == noErr, let block else { return recordError(st) }
        st = nalData.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: len)
        }
        guard st == noErr else { return recordError(st) }

        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMTime(value: ptsUs, timescale: 1_000_000),
                                        decodeTimeStamp: .invalid)
        var sampleSize = len
        var sample: CMSampleBuffer?
        st = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
                                       formatDescription: format, sampleCount: 1,
                                       sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                       sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
                                       sampleBufferOut: &sample)
        guard st == noErr, let sample else { return recordError(st) }

        let errorsBefore = lock.withLock { totalErrorCount }
        st = VTDecompressionSessionDecodeFrame(s, sampleBuffer: sample,
                                               flags: [._1xRealTimePlayback],
                                               infoFlagsOut: nil) { [weak self] status, _, image, pts, _ in
            guard let self else { return }
            guard status == noErr, let image else {
                // Counted only: the session must not be rebuilt from inside its
                // own callback, `decode` does that once DecodeFrame returns.
                self.lock.withLock { self.totalErrorCount += 1; self.consecutiveErrors += 1 }
                return
            }
            let us = pts.timescale == 1_000_000 ? pts.value
                : Int64((Double(pts.value) / Double(pts.timescale)) * 1e6)
            self.onFrame?(image, us)
        }
        guard st == noErr else { return recordError(st) }
        let (callbackFailed, needRebuild) = lock.withLock {
            let failed = totalErrorCount != errorsBefore
            if !failed { consecutiveErrors = 0 }
            return (failed, consecutiveErrors >= Self.maxConsecutiveErrors)
        }
        if callbackFailed && needRebuild { rebuildSession() }
        return .accepted
    }

    /// Counts a submission error; after `maxConsecutiveErrors` in a row the
    /// session is rebuilt and the keyframe gate re-armed.
    private func recordError(_ st: OSStatus) -> HevcDecodeResult {
        let needRebuild = lock.withLock {
            totalErrorCount += 1
            consecutiveErrors += 1
            return consecutiveErrors >= Self.maxConsecutiveErrors
        }
        if needRebuild { rebuildSession() }
        return .failed(st)
    }

    private func rebuildSession() {
        close()
        try? createSession()
    }
}
