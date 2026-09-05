import Foundation

/// Annex-B conversion for `--dump` only. Portiert aus usbcam-sim/AnnexB.swift; die
/// Wire-Nutzlast bleibt unveraendert laengenpraefixiert (PROTOCOL.md 4.6).
enum AnnexB {
    static let startCode = Data([0x00, 0x00, 0x00, 0x01])

    /// VPS/SPS/PPS aus dem hvcC-Record, in Reihenfolge. nil bei kaputtem Record.
    static func parameterSets(fromHvcc hvcc: Data) -> [Data]? {
        let b = [UInt8](hvcc)
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

    /// 4-Byte-BE-laengenpraefixierte NALs -> Startcode-Rahmung. nil bei Rahmenfehler.
    /// `nalCount` zaehlt die gelesenen NAL-Einheiten mit.
    static func convert(lengthPrefixed data: Data, nalCount: inout Int) -> Data? {
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
            nalCount += 1
        }
        return offset == b.count ? out : nil
    }
}

/// Schreibt Annex-B nach `--dump`: Parametersaetze vor jedem Keyframe, dann die NALs.
final class AnnexBWriter {
    private let handle: FileHandle
    private var parameterSets: [Data] = []

    init(path: String) throws {
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let h = FileHandle(forWritingAtPath: path) else {
            throw RecvError.io("cannot open dump file \(path)")
        }
        h.truncateFile(atOffset: 0)
        self.handle = h
    }

    func setParameterSets(hvcc: Data) throws {
        guard let sets = AnnexB.parameterSets(fromHvcc: hvcc), !sets.isEmpty else {
            throw RecvError.protocolViolation("hvcC record is malformed or carries no parameter sets")
        }
        parameterSets = sets
    }

    func write(nalData: Data, isKeyframe: Bool) throws -> Int {
        var nals = 0
        guard let body = AnnexB.convert(lengthPrefixed: nalData, nalCount: &nals) else {
            throw RecvError.protocolViolation("VIDEO payload is not 4-byte-BE length prefixed")
        }
        var out = Data()
        if isKeyframe {
            for set in parameterSets { out.append(AnnexB.startCode); out.append(set) }
        }
        out.append(body)
        handle.write(out)
        return nals
    }

    func close() { try? handle.close() }
}
