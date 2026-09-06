import AudioToolbox
import Foundation

/// ADTS framing for the `--dump-audio` file.
///
/// AUDIO carries raw access units (PROTOCOL.md 4.10), which no container-less
/// tool can parse. Prefixing each with a 7-byte ADTS header (no CRC) makes the
/// dump readable by `ffprobe`/`ffmpeg`.
enum Adts {
    static let headerSize = 7

    /// ISO/IEC 14496-3 sampling frequency index table.
    static let sampleRates = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000,
                              24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350]

    static func sampleRateIndex(_ rate: Int) -> Int? { sampleRates.firstIndex(of: rate) }

    /// Builds the 7-byte header for one access unit.
    ///
    /// - Parameters:
    ///   - payloadLength: size of the raw AAC frame that follows.
    ///   - objectType: MPEG-4 audio object type, 2 = AAC-LC (`IucmAudioCodec.aacLC`).
    /// - Returns: the header, or nil when a field does not fit ADTS (unknown sample
    ///   rate, channel count out of range, frame longer than 13 bits).
    static func header(payloadLength: Int, sampleRate: Int, channels: Int,
                       objectType: Int = 2) -> Data? {
        guard payloadLength > 0,
              let srIndex = sampleRateIndex(sampleRate),
              (1...7).contains(channels),
              (1...4).contains(objectType) else { return nil }
        let frameLength = payloadLength + headerSize
        guard frameLength < (1 << 13) else { return nil }

        var h = [UInt8](repeating: 0, count: headerSize)
        h[0] = 0xFF                                     // syncword 11111111
        h[1] = 0xF1                                     // syncword 1111, MPEG-4, layer 00, no CRC
        h[2] = UInt8(((objectType - 1) << 6) | (srIndex << 2) | ((channels >> 2) & 0x01))
        h[3] = UInt8(((channels & 0x03) << 6) | ((frameLength >> 11) & 0x03))
        h[4] = UInt8((frameLength >> 3) & 0xFF)
        h[5] = UInt8(((frameLength & 0x07) << 5) | 0x1F)  // buffer fullness = VBR
        h[6] = 0xFC                                     // 1 raw data block in this frame
        return Data(h)
    }
}

/// Decodes raw AAC access units to Float32 PCM — the receiver's proof that what
/// AUDIO delivered is actually decodable, mirroring what the plugin will do.
final class AacDecoder {
    let sampleRate: Double
    let channels: UInt32

    private var converter: AudioConverterRef?
    private var pcm: UnsafeMutablePointer<Float>
    /// Samples per AAC-LC access unit.
    static let samplesPerFrame = 1024
    private let maxFrames = 2048

    /// Access unit currently being fed to the converter; the input callback hands
    /// out a pointer into it, so it must outlive the `FillComplexBuffer` call.
    private var pendingBuffer: UnsafeMutablePointer<UInt8>
    private var pendingSize = 0
    private var pendingConsumed = true
    private var pendingDescription = AudioStreamPacketDescription()

    init(sampleRate: Double, channels: UInt32, asc: Data) throws {
        self.sampleRate = sampleRate
        self.channels = channels
        self.pcm = .allocate(capacity: maxFrames * Int(max(1, channels)))
        self.pendingBuffer = .allocate(capacity: 8192)

        var input = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0)
        var output = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * channels,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4 * channels,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0)

        var converter: AudioConverterRef?
        let status = AudioConverterNew(&input, &output, &converter)
        guard status == noErr, let converter else {
            pcm.deallocate(); pendingBuffer.deallocate()
            throw RecvError.protocolViolation("AudioConverterNew (AAC decode) failed: \(status)")
        }
        self.converter = converter

        // The AudioSpecificConfig from AUDIO_CONFIG primes the decoder (PROTOCOL.md 4.9).
        if !asc.isEmpty {
            var cookie = [UInt8](asc)
            let st = AudioConverterSetProperty(converter, kAudioConverterDecompressionMagicCookie,
                                              UInt32(cookie.count), &cookie)
            if st != noErr { logLine("WARN    AAC magic cookie rejected (\(st)) — decoding without it") }
        }
    }

    deinit {
        if let converter { AudioConverterDispose(converter) }
        pcm.deallocate()
        pendingBuffer.deallocate()
    }

    /// Decodes one access unit and returns the number of PCM sample frames produced.
    func decode(frame: Data) throws -> Int {
        guard let converter else { throw RecvError.protocolViolation("AAC decoder is gone") }
        guard !frame.isEmpty, frame.count <= 8192 else {
            throw RecvError.protocolViolation("AUDIO frame of \(frame.count) bytes is not an AAC access unit")
        }
        frame.withUnsafeBytes { raw in
            pendingBuffer.update(from: raw.bindMemory(to: UInt8.self).baseAddress!, count: frame.count)
        }
        pendingSize = frame.count
        pendingConsumed = false

        // Output is LPCM with one frame per packet: ask for exactly one access unit
        // worth of samples, so the converter never pulls a second input packet — a
        // callback returning 0 packets would look like end of stream and latch.
        var packets = UInt32(AacDecoder.samplesPerFrame)
        var status: OSStatus = noErr
        let byteCapacity = UInt32(AacDecoder.samplesPerFrame * Int(channels) * 4)
        var list = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: channels,
                                  mDataByteSize: byteCapacity,
                                  mData: UnsafeMutableRawPointer(pcm)))
        status = AudioConverterFillComplexBuffer(
            converter, aacDecoderInputProc, Unmanaged.passUnretained(self).toOpaque(),
            &packets, &list, nil)
        // noErr with 0 packets happens while the decoder primes; only hard errors fail.
        guard status == noErr || status == kAudioConverterErr_UnspecifiedError else {
            throw RecvError.protocolViolation("AAC decode failed: \(status)")
        }
        return Int(list.mBuffers.mDataByteSize) / (4 * Int(channels))
    }

    fileprivate func provideInput(_ ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
                                  _ ioData: UnsafeMutablePointer<AudioBufferList>,
                                  _ outDesc: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?) -> OSStatus {
        if pendingConsumed {
            ioNumberDataPackets.pointee = 0
            return noErr
        }
        pendingConsumed = true
        pendingDescription = AudioStreamPacketDescription(mStartOffset: 0,
                                                          mVariableFramesInPacket: 0,
                                                          mDataByteSize: UInt32(pendingSize))
        ioNumberDataPackets.pointee = 1
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mNumberChannels = channels
        ioData.pointee.mBuffers.mDataByteSize = UInt32(pendingSize)
        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(pendingBuffer)
        withUnsafeMutablePointer(to: &pendingDescription) { outDesc?.pointee = $0 }
        return noErr
    }
}

private let aacDecoderInputProc: AudioConverterComplexInputDataProc = {
    _, ioNumberDataPackets, ioData, outDataPacketDescription, inUserData in
    guard let inUserData else {
        ioNumberDataPackets.pointee = 0
        return kAudio_ParamError
    }
    let decoder = Unmanaged<AacDecoder>.fromOpaque(inUserData).takeUnretainedValue()
    return decoder.provideInput(ioNumberDataPackets, ioData, outDataPacketDescription)
}
