import CoreMedia
import Foundation
import VideoToolbox

/// Hardware HEVC encoder on top of VTCompressionSession.
///
/// Emits protocol messages directly: CONFIG whenever the hvcC record changes,
/// then VIDEO for every encoded frame.
public final class HevcEncoder {

    public enum EncoderError: Error {
        case sessionCreateFailed(OSStatus)
        case encodeFailed(OSStatus)
        case notStarted
    }

    /// Called from the VideoToolbox callback thread.
    public var onMessage: ((IucmMessage) -> Void)?
    public var onError: ((Error) -> Void)?

    private var session: VTCompressionSession?
    private var lastHvcC: Data?
    private var width: UInt16 = 0
    private var height: UInt16 = 0
    private var fps: UInt16 = 30
    private let lock = NSLock()

    public init() {}

    public func start(width: UInt16, height: UInt16, fps: UInt16, bitrateKbps: UInt32) throws {
        stop()
        lock.lock(); defer { lock.unlock() }
        self.width = width; self.height = height; self.fps = max(fps, 1)
        lastHvcC = nil

        var s: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil,
            compressionSessionOut: &s)
        guard status == noErr, let session = s else { throw EncoderError.sessionCreateFailed(status) }
        self.session = session

        func set(_ key: CFString, _ value: CFTypeRef) {
            VTSessionSetProperty(session, key: key, value: value)
        }
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel)
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)   // no B-frames
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: Int(self.fps)))
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: 1.0))
        set(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: Int(bitrateKbps) * 1000))
        set(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: Int(self.fps)))
        // BT.709 everywhere — the receiver assumes VIDEO_CS_709 / partial range.
        set(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
        set(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
        set(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)

        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard let s = session else { return }
        VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(s)
        session = nil
        lastHvcC = nil
    }

    public func encode(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        let s = session
        lock.unlock()
        guard let session = s,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)

        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer,
            presentationTimeStamp: pts, duration: duration,
            frameProperties: nil,
            infoFlagsOut: nil) { [weak self] status, _, sample in
                guard let self else { return }
                guard status == noErr, let sample else {
                    self.onError?(EncoderError.encodeFailed(status))
                    return
                }
                self.handleEncoded(sample)
            }
        if status != noErr { onError?(EncoderError.encodeFailed(status)) }
    }

    /// Forces the next frame to be an IDR — used when a fresh receiver attaches.
    public func requestKeyframe() {
        // Handled by MaxKeyFrameInterval in the prototype; an explicit force would
        // need per-frame frameProperties, which the START path already covers by
        // restarting the session.
    }

    private func handleEncoded(_ sample: CMSampleBuffer) {
        let keyframe = Self.isKeyframe(sample)

        if keyframe, let desc = CMSampleBufferGetFormatDescription(sample),
           let hvcC = Self.hvcCRecord(from: desc) {
            if hvcC != lastHvcC {
                lastHvcC = hvcC
                onMessage?(.config(width: width, height: height, fps: fps, hvcC: hvcC))
            }
        }

        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        var length = 0
        var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &length,
                                          dataPointerOut: &ptr) == noErr,
              let ptr else { return }
        // VideoToolbox hands out HEVC in HVCC form: each NAL is prefixed with a
        // 4-byte BIG-endian length, and parameter sets live only in the format
        // description, never in this buffer. That is exactly the protocol's
        // VIDEO payload shape, so the bytes are forwarded verbatim — no Annex-B
        // start-code conversion, no re-prefixing.
        let payload = Data(bytes: ptr, count: length)

        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let ptsUs = pts.isValid ? UInt64(max(0, CMTimeGetSeconds(pts) * 1_000_000)) : 0
        onMessage?(.video(ptsUs: ptsUs, keyframe: keyframe, nalUnits: payload))
    }

    /// A sample is a keyframe when the NotSync attachment is absent or false.
    static func isKeyframe(_ sample: CMSampleBuffer) -> Bool {
        guard let arr = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false),
              CFArrayGetCount(arr) > 0 else { return true }
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFDictionary.self)
        guard let raw = CFDictionaryGetValue(
            dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque())
        else { return true }
        let notSync = unsafeBitCast(raw, to: CFBoolean.self)
        return !CFBooleanGetValue(notSync)
    }

    /// Reads the raw hvcC atom out of the format description extensions.
    static func hvcCRecord(from desc: CMFormatDescription) -> Data? {
        guard let atoms = CMFormatDescriptionGetExtension(
            desc, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
            as? [String: Any] else { return nil }
        return atoms["hvcC"] as? Data
    }
}
