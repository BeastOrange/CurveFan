// CommandHandler.swift -- Pure IPCCommand -> IPCResponse dispatch with SMC operations.
// No socket knowledge; reads/writes through SMCService or FakeSMC.

import Foundation
import CurveFanCore
import Darwin
import os

struct CommandHandler: Sendable {
    let smc: SMCService
    let fakeSMC: Bool

    /// Decodes an IPCCommand into the corresponding IPCResponse.
    /// Never throws; SMC errors are surfaced as failure responses.
    func respond(to command: IPCCommand) async -> IPCResponse {
        do {
            switch command {
            case .readKey(let key):
                let value = try await readKey(key)
                return IPCResponse(success: true, value: value, error: nil)
            case .readKeyData(let key):
                let payload = try await readKeyData(key)
                return IPCResponse(success: true, value: nil, data: payload.bytes, dataType: payload.dataType, error: nil)
            case .readKeysData(let keys):
                var batch: [String: SMCKeyData] = [:]
                for key in keys {
                    guard let payload = try? await readKeyData(key) else { continue }
                    batch[key] = SMCKeyData(data: payload.bytes, dataType: payload.dataType)
                }
                return IPCResponse(success: true, value: nil, batch: batch, error: nil)
            case .writeFanRPM(let fan, let rpm):
                try await writeFanRPM(fan: fan, rpm: rpm)
                return IPCResponse(success: true, value: nil, error: nil)
            case .setFanMode(let fan, let mode):
                try await setFanMode(fan: fan, mode: mode)
                return IPCResponse(success: true, value: nil, error: nil)
            case .unlockFanControl(let fan):
                try await unlockFanControl(fan: fan)
                return IPCResponse(success: true, value: nil, error: nil)
            case .restoreFanControl(let fan):
                try await restoreFanControl(fan: fan)
                return IPCResponse(success: true, value: nil, error: nil)
            case .getFanInfo(let fan):
                let info = try await getFanInfo(fan: fan)
                return IPCResponse(success: true, value: nil, fanInfo: info, error: nil)
            case .ping:
                return IPCResponse(success: true, value: nil, error: nil)
            }
        } catch {
            os_log(.error, "command failed: %{public}@", error.localizedDescription)
            return IPCResponse(success: false, value: nil, error: error.localizedDescription)
        }
    }

    /// Restores all fans to auto mode for graceful shutdown. Idempotent.
    func restoreAllFansForCleanup() async {
        if fakeSMC { return }
        do {
            try await smc.open()
        } catch {
            os_log(.error, "cleanup failed: %{public}@", error.localizedDescription)
            return
        }
        do {
            let count = try await currentFanCount()
            for fan in 0..<count {
                do {
                    try await restoreFanControl(fan: fan)
                } catch {
                    os_log(.error, "restore failed for fan %{public}d: %{public}@", fan, error.localizedDescription)
                }
            }
        } catch {
            os_log(.error, "cleanup failed: %{public}@", error.localizedDescription)
        }
        try? await smc.close()
    }

    private func readKey(_ key: String) async throws -> Double {
        if fakeSMC {
            return try FakeSMC.readKey(key)
        }
        let payload = try await readKeyData(key)
        return try SMCDecoder.shared.decode(rawValue: payload.dataType, bytes: payload.bytes)
    }

    private func readKeyData(_ key: String) async throws -> (bytes: [UInt8], dataType: UInt32) {
        try validateSMCKey(key)
        if fakeSMC {
            return try FakeSMC.readKeyData(key)
        }
        let bytes = try await smc.readData(key)
        let info = try await smc.keyInfo(key)
        return (bytes, info.dataType)
    }

    private func writeFanRPM(fan: Int, rpm: Int) async throws {
        if fakeSMC {
            try await validateFanIndex(fan)
            guard (1200...7200).contains(rpm) else {
                throw SMCError.invalidData("RPM \(rpm) is outside 1200-7200")
            }
            return
        }
        let info = try await getFanInfo(fan: fan)
        let clamped = max(Int(info.minRPM), min(Int(info.maxRPM), rpm))
        guard clamped == rpm else {
            throw SMCError.invalidData("RPM \(rpm) is outside \(Int(info.minRPM))-\(Int(info.maxRPM))")
        }
        let bytes = try SMCDecoder.shared.encode(Double(rpm), as: .flt)
        try await smc.writeData(String(format: "F%dTg", fan), bytes: bytes)
    }

    private func setFanMode(fan: Int, mode: Int) async throws {
        try await validateFanIndex(fan)
        guard FanMode(rawValue: mode) != nil else {
            throw SMCError.invalidData("unsupported fan mode \(mode)")
        }
        if fakeSMC { return }
        let key = try await modeKey(for: fan)
        try await smc.writeData(key, bytes: SMCDecoder.shared.encode(Double(mode), as: .ui8))
    }

    private func unlockFanControl(fan: Int) async throws {
        try await validateFanIndex(fan)
        if fakeSMC { return }
        let chip = ChipGen.current() ?? .m5Gen
        if chip == .m5Gen {
            try await setFanMode(fan: fan, mode: FanMode.manual.rawValue)
            return
        }
        try await smc.writeData("Ftst", bytes: try SMCDecoder.shared.encode(1, as: .ui8))
        for _ in 0..<100 {
            let bytes = try await smc.readData(try await modeKey(for: fan))
            if Int(try SMCDecoder.shared.decode(type: .ui8, bytes: bytes)) != FanMode.system.rawValue {
                break
            }
            usleep(100_000)
        }
        try await setFanMode(fan: fan, mode: FanMode.manual.rawValue)
    }

    private func restoreFanControl(fan: Int) async throws {
        if fakeSMC {
            try await validateFanIndex(fan)
            return
        }
        try await setFanMode(fan: fan, mode: FanMode.auto.rawValue)
        if ChipGen.current() != .m5Gen {
            try await smc.writeData("Ftst", bytes: SMCDecoder.shared.encode(0, as: .ui8))
        }
    }

    private func getFanInfo(fan: Int) async throws -> FanInfo {
        if fakeSMC {
            return try FakeSMC.fanInfo(fan: fan)
        }
        let fanCount = try await currentFanCount()
        try await validateFanIndex(fan, fanCount: fanCount)
        let actual = try await readKey(String(format: "F%dAc", fan))
        let minimum = try await readKey(String(format: "F%dMn", fan))
        let maximum = try await readKey(String(format: "F%dMx", fan))
        let modeBytes = try await smc.readData(try await modeKey(for: fan))
        let modeValue = Int(try SMCDecoder.shared.decode(type: .ui8, bytes: modeBytes))
        return FanInfo(
            fanCount: fanCount,
            actualRPM: actual,
            minRPM: minimum,
            maxRPM: maximum,
            mode: FanMode(rawValue: modeValue) ?? .auto
        )
    }

    private func currentFanCount() async throws -> Int {
        if fakeSMC { return FakeSMC.fanCount }
        let bytes = try await smc.readData("FNum")
        guard let first = bytes.first else { throw SMCError.invalidData("FNum returned no data") }
        return Int(first)
    }

    private func validateFanIndex(_ fan: Int, fanCount: Int? = nil) async throws {
        let count: Int
        if let fanCount {
            count = fanCount
        } else {
            count = try await currentFanCount()
        }
        guard fan >= 0 && fan < count else {
            throw SMCError.invalidData("fan index \(fan) is outside 0-\(max(count - 1, 0))")
        }
    }

    private func validateSMCKey(_ key: String) throws {
        let bytes = Array(key.utf8)
        guard (1...4).contains(bytes.count) else {
            throw SMCError.invalidData("SMC keys must be 1-4 bytes")
        }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else {
            throw SMCError.invalidData("SMC keys must be printable ASCII")
        }
    }

    private func modeKey(for fan: Int) async throws -> String {
        let chip = ChipGen.current() ?? .m5Gen
        let preferred = SMCKeyDB.writableFanModeKey(for: fan, chip: chip) ?? String(format: "F%dMd", fan)
        let fallback = preferred.contains("md") ? String(format: "F%dMd", fan) : String(format: "F%dmd", fan)
        for key in [preferred, fallback] {
            do {
                _ = try await smc.keyInfo(key)
                return key
            } catch {
                continue
            }
        }
        throw SMCError.keyNotFound("fan \(fan) mode key")
    }
}
