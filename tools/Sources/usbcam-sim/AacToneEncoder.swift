import AudioToolbox
import Foundation

/// Generates a 440 Hz sine (Float32, mono, 48 kHz) and encodes it to raw AAC-LC
/// access units with AudioToolbox — the audio counterpart of `TestPatternRenderer`
/// plus `HevcEncoder`.
///
/// One call to `nextFrame()` yields exactly one access unit of
/// `AacToneEncoder.samplesPerFrame` (1024) samples, i.e. what AUDIO carries on the
/// wire (PROTOCOL.md 4.10: one raw AAC frame, no ADTS header).
final class AacToneEncoder {
    /// Samples per AAC-LC access unit; also the sim's audio pacing unit.
    static let samplesPerFrame = 1024

    let sampleRate: Double
    let channels: UInt32
    let toneHz: Double

    private var converter: AudioConverterRef?
    /// Scratch PCM the input callback hands to the converter; owned by this object
    /// so the pointer stays valid for the whole `FillComplexBuffer` call.
    private var pcm: UnsafeMutablePointer<Float>
    private var phase: Double = 0
    private var packetDescription = AudioStreamPacketDescription()

    init(sampleRate: Double = 48_000, channels: UInt32 = 1,
         bitrateBps: UInt32 = 64_000, toneHz: Double = 440) throws {
        self.sampleRate = sampleRate
        self.channels = channels
        self.toneHz = toneHz
        self.pcm = .allocate(capacity: AacToneEncoder.samplesPerFrame * Int(channels))

        var input = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * channels,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4 * channels,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0)
        var output = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: UInt32(AacToneEncoder.samplesPerFrame),
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0)

        var converter: AudioConverterRef?
        let status = AudioConverterNew(&input, &output, &converter)
        guard status == noErr, let converter else {
            pcm.deallocate()
            throw SimError.setupFailed("AudioConverterNew (AAC) failed: \(status)")
        }
        self.converter = converter

        var bitrate = bitrateBps
        // Not fatal: the encoder keeps its default rate if it rejects ours.
        AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate,
                                  UInt32(MemoryLayout<UInt32>.size), &bitrate)
    }

    deinit {
        if let converter { AudioConverterDispose(converter) }
        pcm.deallocate()
    }

    /// The AudioSpecificConfig the encoder wants a decoder to be primed with.
    /// Goes on the wire verbatim as `AudioConfigMessage.asc` (PROTOCOL.md 4.9).
    func magicCookie() throws -> Data {
        guard let converter else { throw SimError.setupFailed("AAC converter is gone") }
        var size: UInt32 = 0
        var writable: DarwinBoolean = false
        var status = AudioConverterGetPropertyInfo(converter, kAudioConverterCompressionMagicCookie,
                                                   &size, &writable)
        guard status == noErr, size > 0 else {
            throw SimError.setupFailed("AAC magic cookie unavailable: \(status)")
        }
        var cookie = [UInt8](repeating: 0, count: Int(size))
        status = AudioConverterGetProperty(converter, kAudioConverterCompressionMagicCookie,
                                           &size, &cookie)
        guard status == noErr else {
            throw SimError.setupFailed("AAC magic cookie read failed: \(status)")
        }
        return Data(cookie[0..<Int(size)])
    }

    /// Encodes the next 1024 tone samples into one raw AAC access unit.
    ///
    /// The encoder may swallow the first calls while it primes, so we keep feeding
    /// until it hands back a packet.
    func nextFrame() throws -> Data {
        guard let converter else { throw SimError.setupFailed("AAC converter is gone") }
        var out = [UInt8](repeating: 0, count: 4096)

        for _ in 0..<8 {
            var packets: UInt32 = 1
            var desc = AudioStreamPacketDescription()
            var status: OSStatus = noErr
            let produced: UInt32 = out.withUnsafeMutableBytes { raw -> UInt32 in
                var list = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(mNumberChannels: channels,
                                          mDataByteSize: UInt32(raw.count),
                                          mData: raw.baseAddress))
                status = AudioConverterFillComplexBuffer(
                    converter, aacToneInputProc, Unmanaged.passUnretained(self).toOpaque(),
                    &packets, &list, &desc)
                return packets
            }
            guard status == noErr else {
                throw SimError.setupFailed("AudioConverterFillComplexBuffer failed: \(status)")
            }
            if produced > 0 {
                let start = Int(desc.mStartOffset)
                let length = Int(desc.mDataByteSize)
                guard length > 0, start + length <= out.count else {
                    throw SimError.setupFailed("AAC packet description out of range")
                }
                packetDescription = desc
                return Data(out[start..<(start + length)])
            }
        }
        throw SimError.setupFailed("AAC encoder produced no packet after 8 input frames")
    }

    // MARK: - Input callback plumbing

    /// Fills `pcm` with the next slice of the sine and hands it to the converter.
    fileprivate func provideInput(_ ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
                                  _ ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let frames = AacToneEncoder.samplesPerFrame
        let step = 2 * Double.pi * toneHz / sampleRate
        for i in 0..<frames {
            let value = Float(0.5 * sin(phase))
            for c in 0..<Int(channels) { pcm[i * Int(channels) + c] = value }
            phase += step
            if phase > 2 * Double.pi { phase -= 2 * Double.pi }
        }
        ioNumberDataPackets.pointee = UInt32(frames)
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mNumberChannels = channels
        ioData.pointee.mBuffers.mDataByteSize = UInt32(frames * Int(channels) * 4)
        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(pcm)
        return noErr
    }
}

/// C callback: the converter pulls PCM through here (`inUserData` is the encoder).
private let aacToneInputProc: AudioConverterComplexInputDataProc = {
    _, ioNumberDataPackets, ioData, outDataPacketDescription, inUserData in
    guard let inUserData else {
        ioNumberDataPackets.pointee = 0
        return kAudio_ParamError
    }
    outDataPacketDescription?.pointee = nil
    let encoder = Unmanaged<AacToneEncoder>.fromOpaque(inUserData).takeUnretainedValue()
    return encoder.provideInput(ioNumberDataPackets, ioData)
}
