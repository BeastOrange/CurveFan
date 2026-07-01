// PeerAuth.swift -- LOCAL_PEERCRED-based authorization for IPC peers.

import Foundation
import Darwin

enum PeerAuth {
    /// Returns true when the connected peer's UID is root, matches the helper's
    /// effective UID, or matches the console user's UID.
    static func peerIsAuthorized(socket fd: Int32) -> Bool {
        var peer = xucred()
        var size = socklen_t(MemoryLayout<xucred>.stride)
        let result = withUnsafeMutablePointer(to: &peer) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<xucred>.stride) { raw in
                getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, raw, &size)
            }
        }
        guard result == 0 else { return false }
        let uid = uid_t(peer.cr_uid)
        return uid == 0 || uid == geteuid() || uid == currentConsoleUID()
    }

    /// UID of the user currently logged in at the console (/dev/console owner).
    static func currentConsoleUID() -> uid_t {
        guard let output = try? shellOutput(["/usr/bin/stat", "-f", "%u", "/dev/console"]),
              let uid = uid_t(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0
        }
        return uid
    }

    private static func shellOutput(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
