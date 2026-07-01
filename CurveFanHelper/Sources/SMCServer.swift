// SMCServer.swift -- Unix socket lifecycle and per-connection accept loop.
// Each connection is handled concurrently on DispatchQueue.global().async.
// JSON encoder/decoder are created per connection to avoid shared mutable state.

import Foundation
import CurveFanCore
import Darwin
import os

final class SMCServer: @unchecked Sendable {
    private let path: String
    private let handler: CommandHandler
    private var listenFD: Int32 = -1

    init(path: String, handler: CommandHandler) {
        self.path = path
        self.handler = handler
    }

    /// Opens the listening socket and starts the accept loop on a background queue.
    /// Fatal on socket/bind/listen failure (same as original behavior).
    func start() {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { fatalError("socket() failed") }
        listenFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { pointer in
            pointer.withMemoryRebound(to: Int8.self, capacity: capacity) { buffer in
                _ = path.withCString { p in strncpy(buffer, p, capacity - 1) }
            }
        }

        let addrLength = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, addrLength)
            }
        }
        guard bindResult == 0 else {
            fatalError("bind() failed: \(String(cString: strerror(errno)))")
        }

        configureSocketPermissions()
        guard listen(fd, 5) == 0 else { fatalError("listen() failed") }
        os_log(.info, "listening on %{public}@", path)

        DispatchQueue.global().async { [self] in
            acceptLoop()
        }
    }

    /// Unlinks the socket path. Safe to call from any queue.
    func stop() {
        unlink(path)
    }

    private func acceptLoop() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { continue }
            DispatchQueue.global().async { [handler] in
                Task {
                    defer { close(client) }
                    guard PeerAuth.peerIsAuthorized(socket: client) else {
                        os_log(.error, "rejected unauthorized IPC peer")
                        return
                    }
let decoder = JSONDecoder()
                let encoder = JSONEncoder()
                do {
                    let request = try receiveFrame(socket: client)
                    let response: IPCResponse
                    if let payload = try? IPCSerializer.decodeRequest(request) {
                        response = await handler.respond(to: payload.command)
                    } else {
                        response = IPCResponse(success: false, value: nil, error: "invalid command")
                    }
                    let responseData = try encoder.encode(response)
                    try sendFrame(responseData, socket: client)
                } catch {
                        os_log(.error, "IPC error: %{public}@", error.localizedDescription)
                    }
                }
            }
        }
    }

    private func configureSocketPermissions() {
        let consoleUID = PeerAuth.currentConsoleUID()
        if consoleUID != 0 {
            chown(path, uid_t(consoleUID), getgid())
            chmod(path, 0o600)
        } else {
            chmod(path, 0o660)
        }
    }
}

private func sendFrame(_ data: Data, socket: Int32) throws {
    let frame = try IPCFraming.encode(data)
    try frame.withUnsafeBytes { raw in
        try sendAll(raw, socket: socket)
    }
}

private func receiveFrame(socket: Int32) throws -> Data {
    var header = [UInt8](repeating: 0, count: 4)
    try readAll(into: &header, socket: socket)
    let length = try IPCFraming.decodeLength(header)
    var payload = [UInt8](repeating: 0, count: length)
    try readAll(into: &payload, socket: socket)
    return Data(payload)
}

private func sendAll(_ bytes: UnsafeRawBufferPointer, socket: Int32) throws {
    guard let base = bytes.baseAddress else { return }
    var sent = 0
    while sent < bytes.count {
        let n = send(socket, base.advanced(by: sent), bytes.count - sent, 0)
        guard n > 0 else { throw SMCError.invalidData("short IPC write") }
        sent += n
    }
}

private func readAll(into buffer: inout [UInt8], socket: Int32) throws {
    var received = 0
    while received < buffer.count {
        let remaining = buffer.count - received
        let n = buffer.withUnsafeMutableBytes { raw in
            recv(socket, raw.baseAddress!.advanced(by: received), remaining, 0)
        }
        guard n > 0 else { throw SMCError.invalidData("short IPC read") }
        received += n
    }
}
