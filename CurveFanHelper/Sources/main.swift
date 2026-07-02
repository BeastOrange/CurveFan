// main.swift -- CurveFanHelper entry point.
// Opens SMC (or fake mode), builds dependencies, starts the server, installs
// signal handling, and blocks on the main run loop until SIGTERM/SIGINT.

import Foundation
import CurveFanCore
import os

@main
enum CurveFanHelperMain {
    static func main() async {
        let socketPath = ProcessInfo.processInfo.environment["CURVEFAN_SOCKET_PATH"] ?? "/var/run/curvefan-helper.socket"
        let fakeSMC = ProcessInfo.processInfo.environment["CURVEFAN_HELPER_FAKE_SMC"] == "1"
        let smc = SMCService.shared

        if fakeSMC {
            os_log(.info, "CurveFanHelper daemon started in fake SMC mode")
        } else {
            do {
                try await smc.open()
            } catch {
                fatalError("SMC open failed: \(error.localizedDescription)")
            }
            os_log(.info, "CurveFanHelper daemon started, SMC connected")
        }

        let handler = CommandHandler(smc: smc, fakeSMC: fakeSMC)
        let server = SMCServer(path: socketPath, handler: handler)
        await server.start()

        let signals = SignalHandling(queue: .global(qos: .userInitiated))
        await signals.install { @Sendable in
            Task {
                await server.stop()
                await handler.restoreAllFansForCleanup()
                exit(0)
            }
        }

        await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in
            // Keep the daemon alive until a signal handler calls exit(0).
        }
    }
}
