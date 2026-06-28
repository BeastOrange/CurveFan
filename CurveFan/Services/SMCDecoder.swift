import Foundation

public final class SMCDecoder: Sendable {
    public static let shared = SMCDecoder()
    private init() {}

    public func decode(type: SMCDataType, bytes: [UInt8]) throws -> Double {
        switch type {
        case .fpe2:
            guard bytes.count >= 2 else { throw SMCError.invalidData("FPE2 needs 2 bytes") }
            return decodeFPE2(bytes)
        case .sp78:
            guard bytes.count >= 2 else { throw SMCError.invalidData("SP78 needs 2 bytes") }
            return decodeSP78(bytes)
        case .flt:
            guard bytes.count >= 4 else { throw SMCError.invalidData("FLT needs 4 bytes") }
            return decodeFLT(bytes)
        case .ui8:
            guard bytes.count >= 1 else { throw SMCError.invalidData("UI8 needs 1 byte") }
            return Double(decodeUI8(bytes))
        case .ui16:
            guard bytes.count >= 2 else { throw SMCError.invalidData("UI16 needs 2 bytes") }
            return Double(decodeUI16(bytes))
        case .ui32:
            guard bytes.count >= 4 else { throw SMCError.invalidData("UI32 needs 4 bytes") }
            return Double(decodeUI32(bytes))
        case .si8:
            guard bytes.count >= 1 else { throw SMCError.invalidData("SI8 needs 1 byte") }
            return Double(Int8(bitPattern: bytes[0]))
        case .ch8:
            return 0
        }
    }

    public func decode(rawValue: UInt32, bytes: [UInt8]) throws -> Double {
        guard let type = SMCDataType(rawValue: rawValue) else {
            throw SMCError.invalidData("Unknown SMC data type: 0x\(String(rawValue, radix: 16))")
        }
        return try decode(type: type, bytes: bytes)
    }

    public func encode(_ value: Double, as type: SMCDataType) throws -> [UInt8] {
        switch type {
        case .flt: return encodeFLT(value)
        case .ui8: return encodeUI8(UInt8(value))
        case .ui16: return encodeUI16(UInt16(value))
        case .ui32: return encodeUI32(UInt32(value))
        default: throw SMCError.invalidData("Cannot encode as \(type.fourCharString)")
        }
    }

    private func decodeFPE2(_ bytes: [UInt8]) -> Double {
        let raw = (Int(bytes[0]) << 8) | Int(bytes[1])
        return Double(raw) / 4.0
    }

    private func decodeSP78(_ bytes: [UInt8]) -> Double {
        let raw = Int16(bitPattern: UInt16((UInt16(bytes[0]) << 8) | UInt16(bytes[1])))
        return Double(raw) / 256.0
    }

    private func decodeFLT(_ bytes: [UInt8]) -> Double {
        let bits = UInt32(bytes[0]) |
            (UInt32(bytes[1]) << 8) |
            (UInt32(bytes[2]) << 16) |
            (UInt32(bytes[3]) << 24)
        return Double(Float(bitPattern: bits))
    }

    private func decodeUI8(_ bytes: [UInt8]) -> Int { Int(bytes[0]) }
    private func decodeUI16(_ bytes: [UInt8]) -> Int { Int((UInt16(bytes[0]) << 8) | UInt16(bytes[1])) }
    private func decodeUI32(_ bytes: [UInt8]) -> Int {
        Int((UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3]))
    }

    private func encodeFLT(_ value: Double) -> [UInt8] {
        let bits = Float(value).bitPattern
        return [
            UInt8(bits & 0xFF),
            UInt8((bits >> 8) & 0xFF),
            UInt8((bits >> 16) & 0xFF),
            UInt8((bits >> 24) & 0xFF)
        ]
    }

    private func encodeUI8(_ value: UInt8) -> [UInt8] { [value] }
    private func encodeUI16(_ value: UInt16) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
    private func encodeUI32(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
