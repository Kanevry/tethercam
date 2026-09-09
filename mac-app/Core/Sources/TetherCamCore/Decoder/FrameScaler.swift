// SPDX-License-Identifier: MIT
// FrameScaler.swift
// TetherCam for macOS: fits any decoded geometry (1920x1080, portrait 1080x1920,
// 1280x720, ...) into the one published contract format, 1920x1080 NV12, with
// black bars. Method: VTPixelTransferSession with kVTScalingMode_Letterbox, which
// scales to fit, centres and fills the remainder with black (verified by
// DecoderTests.testScalerLetterboxesPortraitWithBlackColumns). The destination
// comes from a reusable IOSurface-backed CVPixelBufferPool so the CMIO sink can
// hand the buffer over without a copy. A 1920x1080 NV12 input that is already
// IOSurface-backed passes through untouched.

import CoreVideo
import Foundation
import TetherCamContract
import VideoToolbox

public enum FrameScalerError: Error, CustomStringConvertible {
    case sessionCreate(OSStatus)
    case poolCreate(CVReturn)

    public var description: String {
        switch self {
        case .sessionCreate(let s): return "VTPixelTransferSessionCreate failed: \(s)"
        case .poolCreate(let s): return "CVPixelBufferPoolCreate failed: \(s)"
        }
    }
}

/// Thread-safe (internally serialised); one instance per receiver.
public final class FrameScaler {

    public let width: Int
    public let height: Int
    public let pixelFormat: OSType

    private let session: VTPixelTransferSession
    private let pool: CVPixelBufferPool
    private let lock = NSLock()

    public init(width: Int = Int(TetherCamContract.width),
                height: Int = Int(TetherCamContract.height),
                pixelFormat: OSType = TetherCamContract.pixelFormat) throws {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat

        var s: VTPixelTransferSession?
        let st = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &s)
        guard st == noErr, let s else { throw FrameScalerError.sessionCreate(st) }
        VTSessionSetProperty(s, key: kVTPixelTransferPropertyKey_ScalingMode, value: kVTScalingMode_Letterbox)
        session = s

        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        let poolAttrs: [CFString: Any] = [kCVPixelBufferPoolMinimumBufferCountKey: 4]
        var p: CVPixelBufferPool?
        let rc = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary,
                                         attrs as CFDictionary, &p)
        guard rc == kCVReturnSuccess, let p else { throw FrameScalerError.poolCreate(rc) }
        pool = p
    }

    deinit {
        VTPixelTransferSessionInvalidate(session)
    }

    /// True when `buffer` can be published as-is (no scale, no copy).
    public func isPassThrough(_ buffer: CVPixelBuffer) -> Bool {
        CVPixelBufferGetWidth(buffer) == width
            && CVPixelBufferGetHeight(buffer) == height
            && CVPixelBufferGetPixelFormatType(buffer) == pixelFormat
            && CVPixelBufferGetIOSurface(buffer) != nil
    }

    /// Returns the input itself when it already matches, else a pool buffer with
    /// the letterboxed/pillarboxed image. nil when the transfer fails.
    public func scale(_ input: CVPixelBuffer) -> CVPixelBuffer? {
        if isPassThrough(input) { return input }
        lock.lock(); defer { lock.unlock() }
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &out) == kCVReturnSuccess,
              let out else { return nil }
        let st = VTPixelTransferSessionTransferImage(session, from: input, to: out)
        return st == noErr ? out : nil
    }
}
