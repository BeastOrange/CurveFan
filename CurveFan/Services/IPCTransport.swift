import Foundation
import Darwin

public enum IPCError: LocalizedError {
    case socketFailed
    case connectFailed(String)
    case noResponse
    case shortWrite
    case invalidFrame(String)
    case daemonError(String)

    public var errorDescription: String? {
        switch self {
        case .socketFailed: "Failed to create socket"
        case .connectFailed(let m): "Failed to connect to daemon: \(m)"
        case .noResponse: "No response from daemon"
        case .shortWrite: "Failed to write complete IPC frame"
        case .invalidFrame(let m): "Invalid IPC frame: \(m)"
        case .daemonError(let m): "Daemon error: \(m)"
        }
    }
}

public protocol IPCTransport: Sendable {
    func roundTrip(_ data: Data) async throws -> Data
}

public struct UnixSocketTransport: IPCTransport {
    public let socketPath: String
    private let ioQueue: DispatchQueue

    public init(socketPath: String) {
        self.socketPath = socketPath
        self.ioQueue = DispatchQueue(label: "com.curvefan.ipc.io.\(socketPath)")
    }

    public func roundTrip(_ data: Data) async throws -> Data {
        let path = socketPath
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                continuation.resume(with: Result { try Self.connectAndRoundTrip(data, socketPath: path) })
            }
        }
    }

    private static func connectAndRoundTrip(_ data: Data, socketPath: String) throws -> Data {
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { throw IPCError.socketFailed }
        defer { close(sock) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutableBytes(of: &addr) { raw in
            let offset = MemoryLayout<sockaddr_un>.offset(of: \.sun_path)!
            _ = socketPath.withCString {
                strncpy(raw.baseAddress!.advanced(by: offset).assumingMemoryBound(to: Int8.self), $0, pathCapacity - 1)
            }
        }
        let al = socklen_t(MemoryLayout<sockaddr_un>.size)
        guard connect(sock, withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 } }, al) == 0 else {
            throw IPCError.connectFailed(String(cString: strerror(errno)))
        }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        try sendFrame(data, socket: sock)
        return try receiveFrame(socket: sock)
    }

    private static func sendFrame(_ data: Data, socket: Int32) throws {
        let frame = try IPCFraming.encode(data)
        try frame.withUnsafeBytes { raw in
            try sendAll(raw, socket: socket)
        }
    }

    private static func receiveFrame(socket: Int32) throws -> Data {
        var header = [UInt8](repeating: 0, count: 4)
        try readAll(into: &header, socket: socket)
        let length = try IPCFraming.decodeLength(header)
        var payload = [UInt8](repeating: 0, count: length)
        try readAll(into: &payload, socket: socket)
        return Data(payload)
    }

    private static func sendAll(_ bytes: UnsafeRawBufferPointer, socket: Int32) throws {
        guard let base = bytes.baseAddress else { return }
        var sent = 0
        while sent < bytes.count {
            let n = Darwin.send(socket, base.advanced(by: sent), bytes.count - sent, 0)
            guard n > 0 else { throw IPCError.shortWrite }
            sent += n
        }
    }

    private static func readAll(into buffer: inout [UInt8], socket: Int32) throws {
        var received = 0
        while received < buffer.count {
            let remaining = buffer.count - received
            let n = buffer.withUnsafeMutableBytes { raw in
                Darwin.recv(socket, raw.baseAddress!.advanced(by: received), remaining, 0)
            }
            guard n > 0 else { throw IPCError.noResponse }
            received += n
        }
    }
}