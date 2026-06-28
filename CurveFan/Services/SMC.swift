import Foundation

public enum SMCError: LocalizedError {
    case serviceNotFound
    case connectFailed(kern_return_t)
    case readFailed(key: String, code: UInt8)
    case writeFailed(key: String, code: UInt8)
    case keyNotFound(String)
    case permissionDenied(String)
    case invalidData(String)

    public var errorDescription: String? {
        switch self {
        case .serviceNotFound: "AppleSMC service not available"
        case .connectFailed(let kr): "SMC connect failed: 0x\(String(kr, radix: 16))"
        case .readFailed(let k, let c): "SMC read failed for '\(k)': code \(c)"
        case .writeFailed(let k, let c): "SMC write failed for '\(k)': code \(c)"
        case .keyNotFound(let k): "SMC key not found: '\(k)'"
        case .permissionDenied(let k): "Permission denied for '\(k)'"
        case .invalidData(let m): "Invalid SMC data: \(m)"
        }
    }
}

public final class SMCService: @unchecked Sendable {
    public static let shared = SMCService()

    private enum Selector: UInt8 {
        case handleYPCEvent = 2
        case readKey = 5
        case writeKey = 6
        case getKeyInfo = 9
    }

    private enum ResultCode {
        static let success: UInt8 = 0
        static let keyNotFound: UInt8 = 132
        static let permissionDenied: UInt8 = 135
    }

    private var conn: io_connect_t = 0
    private let lock = NSLock()

    private init() {}
    deinit { closeIgnoringErrors() }

    public static var smcParamStructSize: Int {
        MemoryLayout<SMCParamStruct>.stride
    }

    public static var driverSelector: UInt32 {
        UInt32(Selector.handleYPCEvent.rawValue)
    }

    public func open() throws {
        lock.lock()
        defer { lock.unlock() }
        guard conn == 0 else { return }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard result == kIOReturnSuccess else { throw SMCError.connectFailed(result) }
    }

    public func close() throws {
        lock.lock()
        defer { lock.unlock() }
        try closeLocked()
    }

    public func readData(_ key: String) throws -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }
        guard conn != 0 else { throw SMCError.invalidData("not connected") }

        let keyCode = fourCharCode(key)
        let keyInfo = try keyInfoLocked(keyCode, keyName: key)
        guard keyInfo.dataSize <= 32 else {
            throw SMCError.invalidData("SMC key '\(key)' is larger than 32 bytes")
        }

        var input = SMCParamStruct()
        input.key = keyCode
        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = Selector.readKey.rawValue

        let output = try callLocked(selector: .handleYPCEvent, input: &input, keyName: key)
        return output.byteArray.prefix(Int(keyInfo.dataSize)).map { $0 }
    }

    public func writeData(_ key: String, bytes: [UInt8]) throws {
        lock.lock()
        defer { lock.unlock() }
        guard conn != 0 else { throw SMCError.invalidData("not connected") }

        let keyCode = fourCharCode(key)
        let keyInfo = try keyInfoLocked(keyCode, keyName: key)
        guard bytes.count == Int(keyInfo.dataSize) else {
            throw SMCError.invalidData("size mismatch for '\(key)': expected \(keyInfo.dataSize), got \(bytes.count)")
        }

        var input = SMCParamStruct()
        input.key = keyCode
        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = Selector.writeKey.rawValue
        input.setBytes(bytes)

        _ = try callLocked(selector: .handleYPCEvent, input: &input, keyName: key)
    }

    public func keyInfo(_ key: String) throws -> (dataSize: Int, dataType: UInt32) {
        lock.lock()
        defer { lock.unlock() }
        guard conn != 0 else { throw SMCError.invalidData("not connected") }

        let info = try keyInfoLocked(fourCharCode(key), keyName: key)
        return (Int(info.dataSize), info.dataType)
    }

    private func closeLocked() throws {
        guard conn != 0 else { return }
        IOServiceClose(conn)
        conn = 0
    }

    private func closeIgnoringErrors() {
        lock.lock()
        defer { lock.unlock() }
        try? closeLocked()
    }

    private func keyInfoLocked(_ keyCode: UInt32, keyName: String) throws -> SMCKeyInfoData {
        var input = SMCParamStruct()
        input.key = keyCode
        input.data8 = Selector.getKeyInfo.rawValue

        let output = try callLocked(selector: .handleYPCEvent, input: &input, keyName: keyName)
        return output.keyInfo
    }

    private func callLocked(selector: Selector, input: inout SMCParamStruct, keyName: String) throws -> SMCParamStruct {
        precondition(MemoryLayout<SMCParamStruct>.stride == 80, "SMCParamStruct must be 80 bytes")

        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let inputSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            conn,
            UInt32(selector.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )

        if result == kIOReturnNotPermitted || result == kIOReturnNotPrivileged {
            throw SMCError.permissionDenied(keyName)
        }
        guard result == kIOReturnSuccess else {
            throw SMCError.invalidData("IOConnectCall failed for '\(keyName)': 0x\(String(result, radix: 16))")
        }

        switch output.result {
        case ResultCode.success:
            return output
        case ResultCode.keyNotFound:
            throw SMCError.keyNotFound(keyName)
        case ResultCode.permissionDenied:
            throw SMCError.permissionDenied(keyName)
        default:
            throw SMCError.invalidData("SMC returned code \(output.result) for '\(keyName)'")
        }
    }

    private func fourCharCode(_ string: String) -> UInt32 {
        string.padding(toLength: 4, withPad: " ", startingAt: 0)
            .utf8
            .prefix(4)
            .reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = emptySMCBytes()

    var byteArray: [UInt8] {
        withUnsafeBytes(of: bytes) { Array($0) }
    }

    mutating func setBytes(_ values: [UInt8]) {
        withUnsafeMutableBytes(of: &bytes) { raw in
            for index in 0..<raw.count {
                raw[index] = 0
            }
            for index in 0..<min(values.count, raw.count) {
                raw[index] = values[index]
            }
        }
    }
}

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private func emptySMCBytes() -> SMCBytes {
    (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}
