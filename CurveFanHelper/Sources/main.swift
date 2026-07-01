// main.swift -- CurveFanHelper entry point.
// Opens SMC (or fake mode), builds dependencies, starts the server, installs
// signal handling, and blocks on the main run loop until SIGTERM/SIGINT.

import Foundation
import CurveFanCore
import os

let socketPath = ProcessInfo.processInfo.environment["CURVEFAN_SOCKET_PATH"] ?? "/var/run/curvefan-helper.socket"
let fakeSMC = ProcessInfo.processInfo.environment["CURVEFAN_HELPER_FAKE_SMC"] == "1"
let smc = SMCService.shared

if fakeSMC {
    os_log(.info, "CurveFanHelper daemon started in fake SMC mode")
} else {
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            try await smc.open()
        } catch {
            fatalError("SMC open failed: \(error.localizedDescription)")
        }
        sem.signal()
    }
    sem.wait()
    os_log(.info, "CurveFanHelper daemon started, SMC connected")
}

let handler = CommandHandler(smc: smc, fakeSMC: fakeSMC)
let server = SMCServer(path: socketPath, handler: handler)
server.start()

let signals = SignalHandling(queue: .global(qos: .userInitiated))
signals.install {
    server.stop()
    let sem = DispatchSemaphore(value: 0)
    Task {
        await handler.restoreAllFansForCleanup()
        sem.signal()
    }
    sem.wait()
}

RunLoop.main.run()
