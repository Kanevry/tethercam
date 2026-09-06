import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation

/// Microphone capture and AAC-LC encoding for the audio half of protocol 1.1.
///
/// Hangs an `AVCaptureAudioDataOutput` off the same `AVCaptureSession` the
/// camera already runs on, so the PCM buffers carry presentation timestamps from
/// the *session's* clock — the very clock the video buffers are stamped with.
/// That is what keeps AUDIO and VIDEO on one timeline without any correlation
/// arithmetic on the Mac side.
///
/// The encoder is a plain `AudioConverter` (PCM in, AAC-LC out, 48 kHz mono,
/// 96 kbps, 1024 samples per access unit). Access units leave here raw, without
/// an ADTS header, as `protocol/PROTOCOL.md` section 4 requires.
public final class AudioCapture: NSObject {

    /// Announced once per start, before the first frame: sample rate, channel
    /// count and the encoder's magic cookie (the AudioSpecificConfig the
    /// receiver needs to build its decoder).
    public var onConfig: ((UInt32, UInt8, Data) -> Void)?
    /// One raw AAC access unit with its presentation timestamp in microseconds.
    public var onFrame: ((UInt64, Data) -> Void)?
    /// Fatal for audio only — the caller keeps the video stream running.
    public var onError: ((IucmErrorCode) -> Void)?

    /// Wire-side output format. Fixed by the protocol contract.
    public static let outputSampleRate: Double = 48_000
    public static let outputChannels: UInt32 = 1
    public static let framesPerPacket: UInt32 = 1024
    private static let bitrate: UInt32 = 96_000
    /// Generous ceiling for one AAC access unit; 96 kbps needs ~256 byte.
    private static let maxPacketBytes = 4096

    private let sampleQueue = DispatchQueue(label: "at.gotzendorfer.usbcam.audio")
    private let output = AVCaptureAudioDataOutput()
    private weak var session: AVCaptureSession?
    private var input: AVCaptureDeviceInput?
    private var running = false

    // Encoder state. Touched from `sampleQueue` (frames) and from the caller's
    // session queue (start/stop) — hence the lock.
    private let lock = NSLock()
    private var converter: AudioConverterRef?
    private var inputFormat = AudioStreamBasicDescription()
    private var outputFormat = AudioStreamBasicDescription()
    private var pendingPCM = Data()
    private var inputScratch: UnsafeMutableRawPointer?
    private var inputScratchBytes = 0
    private var outputScratch: UnsafeMutableRawPointer?
    private var configSent = false
    /// Timeline anchor: PTS of the first PCM buffer of this take, in the video
    /// clock's microseconds, plus the number of access units emitted since.
    private var anchorPtsUs: UInt64?
    private var emittedPackets: UInt64 = 0

    deinit {
        inputScratch?.deallocate()
        outputScratch?.deallocate()
        if let converter { AudioConverterDispose(converter) }
    }

    // MARK: - Lifecycle

    /// Attaches microphone input and audio output to `session`. Call from the
    /// session queue; the permission prompt hops off it and comes back.
    ///
    /// Idempotent: a second call while running is a no-op, so a START that only
    /// changes the video format does not interrupt the audio stream.
    public func start(on session: AVCaptureSession, queue: DispatchQueue) {
        guard !running else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            attach(session)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] ok in
                queue.async {
                    guard let self else { return }
                    if ok { self.attach(session) } else { self.onError?(.micDenied) }
                }
            }
        default:
            onError?(.micDenied)
        }
    }

    /// Detaches microphone and output and drops the encoder. Call from the
    /// session queue.
    public func stop() {
        guard running else { return }
        running = false
        output.setSampleBufferDelegate(nil, queue: nil)
        if let session {
            session.beginConfiguration()
            if let input { session.removeInput(input) }
            if session.outputs.contains(output) { session.removeOutput(output) }
            session.commitConfiguration()
        }
        input = nil
        session = nil
        lock.lock()
        if let converter { AudioConverterDispose(converter) }
        converter = nil
        pendingPCM.removeAll(keepingCapacity: false)
        configSent = false
        anchorPtsUs = nil
        emittedPackets = 0
        lock.unlock()
    }

    private func attach(_ session: AVCaptureSession) {
        guard !running else { return }
        guard let mic = AVCaptureDevice.default(for: .audio) else {
            onError?(.micDenied)
            return
        }
        session.beginConfiguration()
        do {
            let deviceInput = try AVCaptureDeviceInput(device: mic)
            guard session.canAddInput(deviceInput) else {
                session.commitConfiguration()
                onError?(.micDenied)
                return
            }
            session.addInput(deviceInput)
            input = deviceInput
            if !session.outputs.contains(output) {
                guard session.canAddOutput(output) else {
                    session.removeInput(deviceInput)
                    session.commitConfiguration()
                    onError?(.micDenied)
                    return
                }
                session.addOutput(output)
            }
            output.setSampleBufferDelegate(self, queue: sampleQueue)
            session.commitConfiguration()
            self.session = session
            running = true
            NSLog("[usbcam] audio on: AAC-LC %d Hz %d ch %d kbps",
                  Int(Self.outputSampleRate), Int(Self.outputChannels), Int(Self.bitrate / 1000))
        } catch {
            session.commitConfiguration()
            NSLog("[usbcam] audio input failed: %@", "\(error)" as NSString)
            onError?(.micDenied)
        }
    }

    // MARK: - Encoder

    /// Builds the converter for the PCM format the session actually delivers.
    /// `lock` must be held.
    private func makeConverter(from asbd: AudioStreamBasicDescription) -> Bool {
        if let old = converter { AudioConverterDispose(old); converter = nil }
        var input = asbd
        var output = AudioStreamBasicDescription(
            mSampleRate: Self.outputSampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: AudioFormatFlags(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: Self.framesPerPacket,
            mBytesPerFrame: 0,
            mChannelsPerFrame: Self.outputChannels,
            mBitsPerChannel: 0,
            mReserved: 0)

        var converterRef: AudioConverterRef?
        var status = AudioConverterNew(&input, &output, &converterRef)
        guard status == noErr, let converterRef else {
            NSLog("[usbcam] audio converter failed (%d)", Int(status))
            return false
        }
        var bitrate = Self.bitrate
        status = AudioConverterSetProperty(converterRef, kAudioConverterEncodeBitRate,
                                           UInt32(MemoryLayout<UInt32>.size), &bitrate)
        if status != noErr {
            // Not fatal: the encoder then picks its own rate for this format.
            NSLog("[usbcam] audio bitrate rejected (%d)", Int(status))
        }
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        _ = AudioConverterGetProperty(converterRef, kAudioConverterCurrentOutputStreamDescription,
                                      &size, &output)

        converter = converterRef
        inputFormat = input
        outputFormat = output
        if outputScratch == nil {
            outputScratch = .allocate(byteCount: Self.maxPacketBytes, alignment: 16)
        }
        return true
    }

    /// Reads the magic cookie and fires `onConfig` once. `lock` must be held.
    private func sendConfigIfPossible() {
        guard !configSent, let converter else { return }
        var size: UInt32 = 0
        var writable: DarwinBoolean = false
        guard AudioConverterGetPropertyInfo(converter, kAudioConverterCompressionMagicCookie,
                                            &size, &writable) == noErr, size > 0 else { return }
        var cookie = Data(count: Int(size))
        let ok = cookie.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return AudioConverterGetProperty(converter, kAudioConverterCompressionMagicCookie,
                                             &size, base) == noErr
        }
        guard ok else { return }
        configSent = true
        let rate = UInt32(outputFormat.mSampleRate.rounded())
        let channels = UInt8(clamping: Int(outputFormat.mChannelsPerFrame))
        let payload = cookie.prefix(Int(size))
        onConfig?(rate, channels, Data(payload))
    }

    /// Hands buffered PCM to the converter. Returns `noErr` with zero packets
    /// once the accumulator runs dry, which ends the fill loop below.
    fileprivate func provideInput(_ packets: UnsafeMutablePointer<UInt32>,
                                  _ ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let bytesPerFrame = Int(inputFormat.mBytesPerFrame)
        guard bytesPerFrame > 0 else { packets.pointee = 0; return noErr }
        let available = pendingPCM.count / bytesPerFrame
        let want = min(Int(packets.pointee), available)
        guard want > 0 else {
            packets.pointee = 0
            ioData.pointee.mBuffers.mData = nil
            ioData.pointee.mBuffers.mDataByteSize = 0
            return noErr
        }
        let bytes = want * bytesPerFrame
        if inputScratchBytes < bytes {
            inputScratch?.deallocate()
            inputScratch = .allocate(byteCount: bytes, alignment: 16)
            inputScratchBytes = bytes
        }
        guard let scratch = inputScratch else { packets.pointee = 0; return noErr }
        pendingPCM.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            scratch.copyMemory(from: base, byteCount: bytes)
        }
        pendingPCM.removeFirst(bytes)
        packets.pointee = UInt32(want)
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mNumberChannels = inputFormat.mChannelsPerFrame
        ioData.pointee.mBuffers.mDataByteSize = UInt32(bytes)
        ioData.pointee.mBuffers.mData = scratch
        return noErr
    }

    /// Drains the converter into whole access units. `lock` must be held.
    private func drain() {
        guard let converter, let outputScratch else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        while true {
            var packets: UInt32 = 1
            var description = AudioStreamPacketDescription()
            var list = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: outputFormat.mChannelsPerFrame,
                                      mDataByteSize: UInt32(Self.maxPacketBytes),
                                      mData: outputScratch))
            let status = AudioConverterFillComplexBuffer(
                converter, audioCaptureInputProc, selfPtr, &packets, &list, &description)
            guard status == noErr else {
                NSLog("[usbcam] audio encode failed (%d)", Int(status))
                onError?(.encoderFailed)
                return
            }
            guard packets > 0, list.mBuffers.mDataByteSize > 0 else { return }
            sendConfigIfPossible()
            let frame = Data(bytes: outputScratch, count: Int(list.mBuffers.mDataByteSize))
            // Same clock as VIDEO: the anchor is a capture-session presentation
            // timestamp, and every further access unit is exactly 1024 samples
            // further along the output rate.
            let pts = (anchorPtsUs ?? 0)
                + emittedPackets * UInt64(Self.framesPerPacket) * 1_000_000
                / UInt64(Self.outputSampleRate)
            emittedPackets &+= 1
            onFrame?(pts, frame)
        }
    }
}

/// Free function: `AudioConverterComplexInputDataProc` is a C function pointer,
/// so it cannot capture context — the instance travels in `userData`.
private let audioCaptureInputProc: AudioConverterComplexInputDataProc = {
    _, packets, ioData, _, userData in
    guard let userData else { packets.pointee = 0; return noErr }
    let capture = Unmanaged<AudioCapture>.fromOpaque(userData).takeUnretainedValue()
    return capture.provideInput(packets, ioData)
}

extension AudioCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        guard running,
              let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else { return }

        var blockBuffer: CMBlockBuffer?
        var list = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &list,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer)
        guard status == noErr, list.mBuffers.mDataByteSize > 0,
              let data = list.mBuffers.mData else { return }

        lock.lock()
        defer { lock.unlock() }
        if converter == nil || inputFormat.mSampleRate != asbd.mSampleRate
            || inputFormat.mChannelsPerFrame != asbd.mChannelsPerFrame {
            // First buffer of the take, or a route change (headset plugged in).
            pendingPCM.removeAll(keepingCapacity: true)
            anchorPtsUs = nil
            emittedPackets = 0
            guard makeConverter(from: asbd) else {
                onError?(.encoderFailed)
                return
            }
        }
        if anchorPtsUs == nil {
            // Identical derivation to HevcEncoder's VIDEO pts, from the same
            // capture-session clock.
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            anchorPtsUs = pts.isValid ? UInt64(max(0, CMTimeGetSeconds(pts) * 1_000_000)) : 0
        }
        pendingPCM.append(Data(bytes: data, count: Int(list.mBuffers.mDataByteSize)))
        drain()
    }
}
