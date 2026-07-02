import Foundation

public actor IPCClient {
    public static let shared = IPCClient()

    public let socketPath: String
    public let transport: any IPCTransport

    public init(transport: any IPCTransport) {
        self.transport = transport
        self.socketPath = ""
    }

    public init(socketPath: String? = nil) {
        let path = socketPath ?? ProcessInfo.processInfo.environment["CURVEFAN_SOCKET_PATH"] ?? "/var/run/curvefan-helper.socket"
        self.socketPath = path
        self.transport = UnixSocketTransport(socketPath: path)
    }

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: socketPath)
    }

    public func send(_ command: IPCCommand) async throws -> IPCResponse {
        let reqData = try IPCSerializer.encode(command)
        let responseData = try await transport.roundTrip(reqData)
        return try IPCSerializer.decode(responseData)
    }

    public func sendLegacy(_ command: IPCCommand) async throws -> IPCResponse {
        let reqData = try JSONEncoder().encode(command)
        let responseData = try await transport.roundTrip(reqData)
        return try IPCSerializer.decode(responseData)
    }

    public func ping() async -> Bool {
        do {
            let resp = try await send(.ping)
            return resp.success
        } catch {
            return false
        }
    }

    public func legacyPing() async -> Bool {
        do {
            let resp = try await sendLegacy(.ping)
            return resp.success
        } catch {
            return false
        }
    }
}
