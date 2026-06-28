import Foundation
import AppKit

public actor FanController {
    public static let shared = FanController()
    private var controlTask: Task<Void, Never>?
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

    public func readKeyValue(_ key: String) async throws -> Double {
        let resp = try await ipc.send(.readKey(key: key))
        guard resp.success, let value = resp.value else {
            throw IPCError.daemonError(resp.error ?? "read failed")
        }
        return value
    }

    public func startCurveControl(fan: Int, curve: FanCurve, sensorKey: String) {
        controlTask?.cancel()
        controlTask = Task {
            while !Task.isCancelled {
                do {
                    let temp = try await readKeyValue(sensorKey)
                    let info = try await getFanInfo(fan)
                    let target = curve.rpm(for: temp, minRPM: Int(info.minRPM), maxRPM: Int(info.maxRPM))
                    if target > 0 {
                        try await unlockAndSetRPM(fan, rpm: target)
                    }
                } catch {
                    NSLog("CurveFan curve control failed: \(error.localizedDescription)")
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    public func stopCurveControl(_ fan: Int) async {
        controlTask?.cancel()
        controlTask = nil
        do {
            try await restoreAuto(fan)
        } catch {
            NSLog("CurveFan restore auto failed: \(error.localizedDescription)")
        }
    }

    public func observeWakeEvents() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
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
