import Foundation

/// Chip generation for Apple Silicon SoCs
public enum ChipGen: String, Codable, CaseIterable, Sendable {
    case m1Gen = "M1"
    case m2Gen = "M2"
    case m3Gen = "M3"
    case m4Gen = "M4"
    case m5Gen = "M5"

    /// Detect the current chip generation from the system
    public static func current() -> ChipGen? {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let brand = buf.withUnsafeBufferPointer { pointer in
            let bytes = pointer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self).lowercased()
        }

        if brand.contains("m5") { return .m5Gen }
        if brand.contains("m4") { return .m4Gen }
        if brand.contains("m3") { return .m3Gen }
        if brand.contains("m2") { return .m2Gen }
        if brand.contains("m1") { return .m1Gen }
        return nil
    }
}

/// SMC data type identifiers (four-character codes)
public enum SMCDataType: UInt32, Codable, Sendable {
    case fpe2 = 0x66706532  // "fpe2" - fixed-point e2, value / 4.0
    case sp78 = 0x73703738  // "sp78" - signed fixed-point, value / 256.0
    case flt  = 0x666c7420  // "flt " - IEEE 754 float32
    case ui8  = 0x75693820  // "ui8 " - unsigned 8-bit
    case ui16 = 0x75693136  // "ui16" - unsigned 16-bit big-endian
    case ui32 = 0x75693332  // "ui32" - unsigned 32-bit big-endian
    case si8  = 0x73693820  // "si8 " - signed 8-bit
    case ch8  = 0x63683820  // "ch8*" - 8-character byte array

    /// Convert four-character code to string for debugging
    var fourCharString: String {
        var value = self.rawValue.bigEndian
        return withUnsafeBytes(of: &value) { String(bytes: $0, encoding: .ascii) ?? "????" }
    }
}

public enum SensorGroup: String, Codable, Sendable, CaseIterable {
    case cpu
    case gpu
    case memory
    case system
    case fan
}

public enum FanMode: Int, Codable, Sendable {
    case auto = 0
    case manual = 1
    case system = 3
}

public enum ConnectionStatus: Sendable {
    case connected
    case disconnected
    case error(String)
}
