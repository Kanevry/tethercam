import Foundation

/// Annex-B conversion for the `--dump` file only.
///
/// The wire format keeps VideoToolbox's 4-byte big-endian length prefixes untouched.
/// A raw `.hevc` file for ffmpeg/ffplay however needs start codes plus the parameter
/// sets in-band, so those are pulled out of the `hvcC` record and prepended to every
/// keyframe.
enum AnnexB {
    static let startCode = Data([0x00, 0x00, 0x00, 0x01])

    /// Extracts VPS/SPS/PPS (and any other arrays) from an `hvcC` record, in order.
    /// Returns nil if the record is malformed.
    static func parameterSets(fromHvcc hvcc: Data) -> [Data]? {
        let b = [UInt8](hvcc)
        // Fixed part of HEVCDecoderConfigurationRecord is 22 bytes; numOfArrays follows.
        guard b.count > 22 else { return nil }
        var offset = 22
        let arrayCount = Int(b[offset]); offset += 1
        var sets: [Data] = []
        for _ in 0..<arrayCount {
            guard offset + 3 <= b.count else { return nil }
            offset += 1 // array_completeness / reserved / NAL_unit_type
            let naluCount = Int(b[offset]) << 8 | Int(b[offset + 1]); offset += 2
            for _ in 0..<naluCount {
                guard offset + 2 <= b.count else { return nil }
                let length = Int(b[offset]) << 8 | Int(b[offset + 1]); offset += 2
                guard offset + length <= b.count else { return nil }
                sets.append(Data(b[offset..<(offset + length)]))
                offset += length
            }
        }
        return sets
    }

    /// Rewrites 4-byte-big-endian length-prefixed NAL units as start-code delimited ones.
    /// Returns nil if the buffer is not well formed.
    static func convert(lengthPrefixed data: Data) -> Data? {
        let b = [UInt8](data)
        var out = Data()
        var offset = 0
        while offset + 4 <= b.count {
            var length = 0
            for i in 0..<4 { length = (length << 8) | Int(b[offset + i]) }
            offset += 4
            guard length > 0, offset + length <= b.count else { return nil }
            out.append(startCode)
            out.append(contentsOf: b[offset..<(offset + length)])
            offset += length
        }
        return offset == b.count ? out : nil
    }
}
