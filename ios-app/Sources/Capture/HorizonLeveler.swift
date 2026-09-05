import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Metal

/// Pure geometry + smoothing for the continuous horizon leveller.
///
/// Kept free of CoreImage and CoreVideo so every number below is unit-testable
/// on the simulator without a camera.
public enum LevelerMath {

    /// Residual roll is clamped to this magnitude. Two reasons:
    /// the fill zoom grows fast (16:9 needs 1.43x at 15 degrees, 2.04x at 60),
    /// and the sector hysteresis (45 + 15 degrees) legitimately lets the residual
    /// reach 60 degrees *while the mount is being turned*. Fully levelling that
    /// transient would punch a 2x crop out of the frame for a second. Clamping
    /// leaves a visible tilt during the turn and a level picture once the sector
    /// has followed, which is the trade Continuity Camera also makes.
    public static let maxResidualDeg: CGFloat = 25

    /// Below this residual change the smoothed value does not move at all —
    /// kills the 0.1-degree sensor noise that would otherwise resample every frame.
    public static let deadBandDeg: CGFloat = 0.3

    /// Exponential time constant of the residual smoother, seconds.
    public static let timeConstant: TimeInterval = 0.8

    /// Signed shortest angle in (-180, 180].
    public static func wrap180(_ a: CGFloat) -> CGFloat {
        var v = a.truncatingRemainder(dividingBy: 360)
        if v > 180 { v -= 360 }
        if v <= -180 { v += 360 }
        return v
    }

    /// Roll left over after the capture connection applied the quantised sector.
    ///
    /// `continuous` and `sector` are both in the `videoRotationAngle` convention
    /// (0 = landscape/charge-port-right, 90 = portrait, counted the same way as
    /// `OrientationMath.continuousAngle`). The connection already rotated the
    /// buffer by `sector`, so `continuous - sector` is exactly what is missing.
    public static func residualAngle(continuous: CGFloat, sector: CGFloat) -> CGFloat {
        wrap180(continuous - sector)
    }

    /// Minimal uniform scale so a source rectangle of the output's aspect ratio,
    /// rotated by `angleDeg`, still covers the whole WxH output rectangle.
    ///
    /// `s = cos d + sin d * max(W/H, H/W)`, `d = |angle|`. At 0 degrees it is 1
    /// (no zoom); it grows monotonically with the tilt.
    public static func fillScale(angleDeg: CGFloat, aspect: CGFloat) -> CGFloat {
        let d = abs(wrap180(angleDeg)) * .pi / 180
        let a = abs(aspect) > 0 ? max(abs(aspect), 1 / abs(aspect)) : 1
        return cos(d) + sin(d) * a
    }

    /// Clamped residual actually handed to the renderer.
    public static func clampResidual(_ deg: CGFloat) -> CGFloat {
        min(max(wrap180(deg), -maxResidualDeg), maxResidualDeg)
    }
}

/// Exponentially smoothed residual angle with dead-band and flat-freeze.
///
/// Pure value type — `update` takes the elapsed time and the gravity confidence
/// explicitly so the whole behaviour can be driven from a test.
public struct ResidualSmoother {
    public private(set) var value: CGFloat = 0
    public private(set) var hasValue = false

    public init() {}

    /// - Parameters:
    ///   - target: raw residual in degrees (already sector-relative).
    ///   - dt: seconds since the previous frame.
    ///   - confidence: in-plane gravity magnitude; below
    ///     `OrientationMath.flatThreshold` the phone is flat, the roll angle is
    ///     numerically meaningless and the residual freezes just like the sector.
    /// - Returns: the value to render with.
    @discardableResult
    public mutating func update(target: CGFloat, dt: TimeInterval, confidence: CGFloat) -> CGFloat {
        guard confidence >= OrientationMath.flatThreshold else { return value }
        let t = LevelerMath.wrap180(target)
        guard hasValue else {
            hasValue = true
            value = t
            return value
        }
        let delta = LevelerMath.wrap180(t - value)
        guard abs(delta) >= LevelerMath.deadBandDeg else { return value }
        let alpha = CGFloat(1 - exp(-max(dt, 0) / LevelerMath.timeConstant))
        value = LevelerMath.wrap180(value + alpha * delta)
        return value
    }

    public mutating func reset() { value = 0; hasValue = false }
}

/// GPU horizon leveller: rotates the already sector-rotated capture buffer by the
/// residual roll, zooms just enough to keep the frame filled, scales down to the
/// target output size and crops centrally — all in one affine transform, one
/// CoreImage pass, one Metal command buffer per frame.
public final class HorizonLeveler {

    /// Which destination pixel format the CIContext renders into.
    public enum RenderPath: String {
        /// Direct into a 420v (NV12 video-range) buffer. Preferred: the encoder
        /// gets exactly the format the capture path already produced.
        case nv12
        /// CoreImage refused to write 420v on this OS/device — render BGRA and
        /// let VideoToolbox do the colour conversion. Costs bandwidth, not fidelity.
        case bgra
    }

    public struct Telemetry {
        public var avgMs: Double = 0
        public var lastResidualDeg: CGFloat = 0
        public var droppedFrames: Int = 0
        public var path: RenderPath = .nv12
        public var outputSize: CGSize = .zero
    }

    public private(set) var path: RenderPath = .nv12

    /// Thread-safe copy of the current counters — the UI reads this from main
    /// while `process` runs on the capture queue.
    public var snapshot: Telemetry {
        telemetryLock.lock(); defer { telemetryLock.unlock() }
        return telemetry
    }

    private let context: CIContext
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero
    private var poolFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    private var formatDescription: CMFormatDescription?
    private let busy = NSLock()
    private let telemetryLock = NSLock()
    private var telemetry = Telemetry()

    // Rolling per-frame cost, exponential moving average over ~30 frames.
    private var avgMs: Double = 0
    private var frames = 0
    private var dropped = 0

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let options: [CIContextOption: Any] = [
            .workingColorSpace: NSNull(),
            .cacheIntermediates: false,
            .name: "usbcam-leveler",
        ]
        context = CIContext(mtlDevice: device, options: options)
        path = HorizonLeveler.probeNV12(context: context) ? .nv12 : .bgra
        telemetryLock.lock(); telemetry.path = path; telemetryLock.unlock()
        NSLog("[usbcam] leveler render path=%@", path.rawValue as NSString)
    }

    /// One-shot startup probe: render a known grey through the context into a
    /// 420v buffer and read the luma back. If CoreImage cannot write biplanar
    /// YCbCr on this OS the result is black (or the render is a no-op) and the
    /// BGRA bridge is used instead. Cheap, 64x64, runs once.
    static func probeNV12(context: CIContext) -> Bool {
        let fmt = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        guard let src = makeBuffer(64, 64, fmt), let dst = makeBuffer(64, 64, fmt) else { return false }
        fillLuma(src, 180)
        fillLuma(dst, 0)
        tag709(src)
        tag709(dst)
        let image = CIImage(cvPixelBuffer: src)
        context.render(image, to: dst, bounds: CGRect(x: 0, y: 0, width: 64, height: 64),
                       colorSpace: nil)
        return centreLuma(dst).map { abs(Int($0) - 180) < 40 } ?? false
    }

    /// Levels one capture sample. Returns a new sample buffer carrying the
    /// original presentation timestamp and duration, or `nil` when the frame was
    /// dropped (leveller still busy) or could not be rendered.
    ///
    /// - Parameters:
    ///   - sample: NV12 buffer straight from `AVCaptureVideoDataOutput`, already
    ///     coarse-rotated by `connection.videoRotationAngle`.
    ///   - residualDeg: smoothed residual roll in degrees, `videoRotationAngle`
    ///     convention (positive = the image must be rotated clockwise).
    ///   - target: requested output size in landscape orientation, e.g. 1920x1080.
    ///     The actual output follows the input's orientation (a portrait mount
    ///     yields 1080x1920) so the encoder sees the same geometry it always did.
    public func process(_ sample: CMSampleBuffer, residualDeg: CGFloat,
                        target: CGSize) -> CMSampleBuffer? {
        guard busy.try() else {
            telemetryLock.lock()
            dropped += 1
            telemetry.droppedFrames = dropped
            telemetryLock.unlock()
            return nil
        }
        defer { busy.unlock() }
        guard let src = CMSampleBufferGetImageBuffer(sample) else { return nil }

        let t0 = CFAbsoluteTimeGetCurrent()
        let sw = CGFloat(CVPixelBufferGetWidth(src))
        let sh = CGFloat(CVPixelBufferGetHeight(src))
        guard sw > 0, sh > 0 else { return nil }

        let out = Self.outputSize(source: CGSize(width: sw, height: sh), target: target)
        guard let dst = buffer(for: out) else { return nil }
        // Only the colour tags travel. Propagating *all* attachments would drag a
        // 4K clean-aperture/pixel-aspect description onto a 1080p buffer.
        Self.copyColourTags(from: src, to: dst)

        let delta = LevelerMath.clampResidual(residualDeg)
        let base = min(out.width / sw, out.height / sh)
        let scale = base * LevelerMath.fillScale(angleDeg: delta,
                                                 aspect: out.width / out.height)

        // y-up CoreImage space: a positive rotationAngle turns counter-clockwise,
        // while videoRotationAngle counts clockwise — hence the minus.
        var t = CGAffineTransform(translationX: -sw / 2, y: -sh / 2)
        t = t.concatenating(CGAffineTransform(rotationAngle: -delta * .pi / 180))
        t = t.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        t = t.concatenating(CGAffineTransform(translationX: out.width / 2, y: out.height / 2))

        let image = CIImage(cvPixelBuffer: src).transformed(by: t)
        context.render(image, to: dst,
                       bounds: CGRect(origin: .zero, size: out),
                       colorSpace: nil)

        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        frames += 1
        avgMs = frames < 2 ? ms : avgMs * 0.94 + ms * 0.06
        telemetryLock.lock()
        telemetry.avgMs = avgMs
        telemetry.lastResidualDeg = delta
        telemetry.outputSize = out
        telemetryLock.unlock()

        return Self.wrap(dst, like: sample, description: &formatDescription)
    }

    /// Safe to call from any queue: takes the same lock `process` holds.
    public func reset() {
        busy.lock(); defer { busy.unlock() }
        pool = nil
        poolSize = .zero
        formatDescription = nil
        frames = 0
        avgMs = 0
    }

    /// Output keeps the *orientation* of the delivered buffer and the *size* of
    /// the request: a landscape frame becomes 1920x1080, a portrait one 1080x1920.
    static func outputSize(source: CGSize, target: CGSize) -> CGSize {
        let long = max(target.width, target.height)
        let short = min(target.width, target.height)
        return source.width >= source.height
            ? CGSize(width: long, height: short)
            : CGSize(width: short, height: long)
    }

    // MARK: - Buffer plumbing

    private func buffer(for size: CGSize) -> CVPixelBuffer? {
        let want: OSType = path == .nv12
            ? kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            : kCVPixelFormatType_32BGRA
        if pool == nil || poolSize != size || poolFormat != want {
            pool = Self.makePool(Int(size.width), Int(size.height), want)
            poolSize = size
            poolFormat = want
            formatDescription = nil
        }
        guard let pool else { return nil }
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &out) == kCVReturnSuccess
        else { return nil }
        return out
    }

    static func makePool(_ w: Int, _ h: Int, _ format: OSType) -> CVPixelBufferPool? {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(format),
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
        ]
        var pool: CVPixelBufferPool?
        let poolAttrs: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 4]
        guard CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary,
                                      attrs as CFDictionary, &pool) == kCVReturnSuccess
        else { return nil }
        return pool
    }

    static func wrap(_ pixelBuffer: CVPixelBuffer, like sample: CMSampleBuffer,
                     description: inout CMFormatDescription?) -> CMSampleBuffer? {
        if description == nil {
            var d: CMFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                formatDescriptionOut: &d) == noErr else { return nil }
            description = d
        }
        guard let desc = description else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sample),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample),
            decodeTimeStamp: .invalid)
        var out: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
            formatDescription: desc, sampleTiming: &timing,
            sampleBufferOut: &out) == noErr else { return nil }
        return out
    }

    // MARK: - Probe helpers

    static func makeBuffer(_ w: Int, _ h: Int, _ format: OSType) -> CVPixelBuffer? {
        var buf: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, format,
                                  attrs as CFDictionary, &buf) == kCVReturnSuccess
        else { return nil }
        return buf
    }

    static func fillLuma(_ b: CVPixelBuffer, _ value: UInt8) {
        CVPixelBufferLockBaseAddress(b, [])
        defer { CVPixelBufferUnlockBaseAddress(b, []) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(b, 0) else { return }
        let stride = CVPixelBufferGetBytesPerRowOfPlane(b, 0)
        let rows = CVPixelBufferGetHeightOfPlane(b, 0)
        memset(base, Int32(value), stride * rows)
        if CVPixelBufferGetPlaneCount(b) > 1,
           let c = CVPixelBufferGetBaseAddressOfPlane(b, 1) {
            memset(c, 128, CVPixelBufferGetBytesPerRowOfPlane(b, 1)
                   * CVPixelBufferGetHeightOfPlane(b, 1))
        }
    }

    static func centreLuma(_ b: CVPixelBuffer) -> UInt8? {
        CVPixelBufferLockBaseAddress(b, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(b, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(b, 0) else { return nil }
        let stride = CVPixelBufferGetBytesPerRowOfPlane(b, 0)
        let y = CVPixelBufferGetHeightOfPlane(b, 0) / 2
        let x = CVPixelBufferGetWidthOfPlane(b, 0) / 2
        return base.advanced(by: y * stride + x).assumingMemoryBound(to: UInt8.self).pointee
    }

    /// BT.709 in, BT.709 out. Missing tags on the source are filled in rather
    /// than left blank — the receiver assumes 709/partial range either way.
    static func copyColourTags(from src: CVPixelBuffer, to dst: CVPixelBuffer) {
        let pairs: [(CFString, CFString)] = [
            (kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2),
            (kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2),
            (kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2),
        ]
        for (key, fallback) in pairs {
            let value = CVBufferGetAttachment(src, key, nil)?.takeUnretainedValue() ?? fallback
            CVBufferSetAttachment(dst, key, value, .shouldPropagate)
        }
    }

    static func tag709(_ b: CVPixelBuffer) {
        CVBufferSetAttachment(b, kCVImageBufferColorPrimariesKey,
                              kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(b, kCVImageBufferTransferFunctionKey,
                              kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(b, kCVImageBufferYCbCrMatrixKey,
                              kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    }
}
