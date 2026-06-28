import Foundation
import Darwin

let socketPath = ProcessInfo.processInfo.environment["CURVEFAN_SOCKET_PATH"] ?? "/var/run/curvefan-helper.socket"
let maxFrameSize = 1_048_576

guard CommandLine.arguments.count == 2,
      let request = CommandLine.arguments[1].data(using: .utf8) else {
    fputs("usage: ipc_send.swift '<json>'\n", stderr)
    exit(2)
}

let sock = socket(AF_UNIX, SOCK_STREAM, 0)
guard sock >= 0 else {
    fputs("socket failed\n", stderr)
    exit(1)
}
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

let connected = withUnsafePointer(to: &addr) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0 else {
    fputs("connect failed: \(String(cString: strerror(errno)))\n", stderr)
    exit(1)
}

func sendAll(_ bytes: UnsafeRawBufferPointer) {
    guard let base = bytes.baseAddress else { return }
    var sent = 0
    while sent < bytes.count {
        let n = Darwin.send(sock, base.advanced(by: sent), bytes.count - sent, 0)
        guard n > 0 else {
            fputs("send failed\n", stderr)
            exit(1)
        }
        sent += n
    }
}

var length = UInt32(request.count).bigEndian
withUnsafeBytes(of: &length) { sendAll($0) }
request.withUnsafeBytes { sendAll($0) }

func readAll(_ count: Int) -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: count)
    var received = 0
    while received < count {
        let remaining = count - received
        let n = buffer.withUnsafeMutableBytes {
            recv(sock, $0.baseAddress!.advanced(by: received), remaining, 0)
        }
        guard n > 0 else {
            fputs("recv failed\n", stderr)
            exit(1)
        }
        received += n
    }
    return buffer
}

let header = readAll(4)
let responseLength = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
guard responseLength > 0 && responseLength <= maxFrameSize else {
    let prefix = String(bytes: header, encoding: .utf8) ?? "\(header)"
    fputs("invalid framed response from helper (prefix: \(prefix)); run 'sudo bash setup.sh' to install the current helper\n", stderr)
    exit(1)
}

let response = Data(readAll(Int(responseLength)))
print(String(data: response, encoding: .utf8) ?? "")
