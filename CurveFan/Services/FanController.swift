import Foundation

public actor FanController {
    public static let shared = FanController()
    private let ipc = IPCClient.shared

    public func getFanInfo(_ fan: Int) async throws -> FanInfo {
        let resp = try await ipc.send(.getFanInfo(fan: fan))
        guard resp.success, let info = resp.fanInfo else {
            throw IPCError.daemonError(resp.error ?? "unknown")
        }
        return info
    }

    public func unlockAndSetRPM(_ fan: Int, rpm: Int) async throws {
        let unlock = try await ipc.send(.unlockFanControl(fan: fan))
        guard unlock.success else { throw IPCError.daemonError(unlock.error ?? "unlock failed") }

        let write = try await ipc.send(.writeFanRPM(fan: fan, rpm: rpm))
        guard write.success else { throw IPCError.daemonError(write.error ?? "write failed") }
    }

    public func restoreAuto(_ fan: Int) async throws {
        let resp = try await ipc.send(.restoreFanControl(fan: fan))
        guard resp.success else { throw IPCError.daemonError(resp.error ?? "restore failed") }
    }

    public func restoreAutoLogging(_ fan: Int) async {
        do {
            try await restoreAuto(fan)
        } catch {
            NSLog("CurveFan restore auto failed: \(error.localizedDescription)")
        }
    }

    public func observeWakeEvents(from source: WakeEventSource) async {
        await source.observeWake { [weak self] in
            guard let self else { return }
            Task {
                do {
                    let info = try await self.getFanInfo(0)
                    if info.mode == .manual {
                        try await self.unlockAndSetRPM(0, rpm: Int(info.actualRPM))
                    }
                } catch {
                    NSLog("CurveFan wake handling failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
