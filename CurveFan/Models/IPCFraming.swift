import Foundation

public enum IPCFramingError: LocalizedError, Equatable {
    case payloadTooLarge
    case emptyFrame
    case invalidLength(UInt32)

    public var errorDescription: String? {
        switch self {
        case .payloadTooLarge: "IPC payload is too large"
        case .emptyFrame: "IPC frame is empty"
        case .invalidLength(let length): "Invalid IPC frame length: \(length)"
        }
    }
}

public enum IPCFraming {
    public static let maxFrameSize = 1_048_576

    public static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else { throw IPCFramingError.emptyFrame }
        guard payload.count <= maxFrameSize else { throw IPCFramingError.payloadTooLarge }

        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        return frame
    }

    public static func decodeLength(_ header: [UInt8]) throws -> Int {
        guard header.count == 4 else { throw IPCFramingError.invalidLength(UInt32(header.count)) }
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0 else { throw IPCFramingError.emptyFrame }
        guard length <= maxFrameSize else { throw IPCFramingError.invalidLength(length) }
        return Int(length)
    }
}
