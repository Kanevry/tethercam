import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

enum SimError: Error, CustomStringConvertible {
    case setupFailed(String)
    case encodeFailed(OSStatus)

    var description: String {
        switch self {
        case .setupFailed(let m): return m
        case .encodeFailed(let s): return "VideoToolbox status \(s)"
        }
    }
}

/// One encoded access unit as it goes on the wire.
struct EncodedFrame {
    var ptsUs: UInt64
    var isKeyframe: Bool
    /// Length-prefixed NAL units, exactly as VideoToolbox produced them
    /// (4-byte big-endian lengths). Passed through unchanged for VIDEO.
    var nalData: Data
    /// Raw `hvcC` atom of the format description this frame belongs to.
    var hvcc: Data?
}

/// Hardware HEVC encoder configured per the spec: realtime, no reordering,
/// keyframe every `fps` frames, BT.709 colour tags, HEVC Main auto level.
final class HevcEncoder {
    private var session: VTCompressionSession?
    let width: Int
    let height: Int
    let fps: Int

    init(width: Int, height: Int, fps: Int, bitrateKbps: Int) throws {
        self.width = width
        self.height = height
        self.fps = fps

        var session: VTCompressionSession?
        let encoderSpec: [String: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true
        ]
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: encoderSpec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil,
            compressionSessionOut: &session)
        guard status == noErr, let session else {
            throw SimError.setupFailed("VTCompressionSessionCreate failed: \(status)")
        }
        self.session = session

        func set(_ key: CFString, _ value: CFTypeRef) throws {
            let st = VTSessionSetProperty(session, key: key, value: value)
            guard st == noErr else { throw SimError.setupFailed("property \(key) failed: \(st)") }
        }
        try set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        try set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        try set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel)
        try set(kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: fps))
        try set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: 1.0))
        try set(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: fps))
        try set(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: bitrateKbps * 1000))
        try set(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
        try set(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
        try set(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    deinit { invalidate() }

    func invalidate() {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }

    /// Encodes one frame. `handler` runs on VideoToolbox's callback queue.
    func encode(_ buffer: CVPixelBuffer, ptsUs: UInt64, handler: @escaping (EncodedFrame) -> Void) throws {
        guard let session else { throw SimError.setupFailed("encoder invalidated") }
        let pts = CMTime(value: CMTimeValue(ptsUs), timescale: 1_000_000)
        let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: buffer, presentationTimeStamp: pts, duration: duration,
            frameProperties: nil, infoFlagsOut: nil
        ) { status, _, sampleBuffer in
            guard status == noErr, let sampleBuffer,
                  CMSampleBufferDataIsReady(sampleBuffer),
                  let frame = Self.makeFrame(sampleBuffer) else { return }
            handler(frame)
        }
        guard status == noErr else { throw SimError.encodeFailed(status) }
    }

    private static func makeFrame(_ sb: CMSampleBuffer) -> EncodedFrame? {
        guard let block = CMSampleBufferGetDataBuffer(sb) else { return nil }
        let length = CMBlockBufferGetDataLength(block)
        var data = Data(count: length)
        let copied: OSStatus = data.withUnsafeMutableBytes { raw in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                       destination: raw.baseAddress!)
        }
        guard copied == noErr else { return nil }

        // A sample is a keyframe unless it is explicitly marked "not sync".
        var isKeyframe = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false)
            as? [[CFString: Any]], let first = attachments.first,
           let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
            isKeyframe = !notSync
        }

        // Convert exactly in the integer domain; going via seconds would round.
        let scaled = CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(sb),
                                        timescale: 1_000_000, method: .roundTowardZero)
        let ptsUs = UInt64(max(0, scaled.value))
        return EncodedFrame(ptsUs: ptsUs, isKeyframe: isKeyframe, nalData: data,
                            hvcc: hvcc(from: CMSampleBufferGetFormatDescription(sb)))
    }

    /// Reads the `hvcC` record out of the format description rather than building it.
    static func hvcc(from formatDescription: CMFormatDescription?) -> Data? {
        guard let fd = formatDescription,
              let atoms = CMFormatDescriptionGetExtension(
                fd, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
                as? [String: Any],
              let hvcc = atoms["hvcC"] as? Data else { return nil }
        return hvcc
    }
}
