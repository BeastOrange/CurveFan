import Foundation

public struct TemperatureReading: Identifiable, Sendable {
    public let id = UUID()
    public let key: String
    public let name: String
    public let group: SensorGroup
    public let value: Double
    public let timestamp: Date
}

public actor TemperatureReader {
    public static let shared = TemperatureReader()
    private let ipc = IPCClient.shared

    public func readings(for chip: ChipGen) async -> [TemperatureReading] {
        let keys = SMCKeyDB.keys(for: .cpu, chip: chip) +
                   SMCKeyDB.keys(for: .gpu, chip: chip) +
                   SMCKeyDB.keys(for: .memory, chip: chip) +
                   SMCKeyDB.keys(for: .system, chip: chip)

        var readings: [TemperatureReading] = []
        for def in keys {
            do {
                let resp = try await ipc.send(.readKeyData(key: def.key))
                guard resp.success, let bytes = resp.data, let dataType = resp.dataType else {
                    throw IPCError.daemonError(resp.error ?? "read failed")
                }
                let value = try SMCDecoder.shared.decode(rawValue: dataType, bytes: bytes)
                readings.append(TemperatureReading(key: def.key, name: def.name, group: def.group, value: value, timestamp: Date()))
            } catch {
                NSLog("CurveFan temperature read failed for \(def.key): \(error.localizedDescription)")
            }
        }
        return readings
    }

    public func stream(interval: TimeInterval = 2.0) -> AsyncStream<[TemperatureReading]> {
        let chip = ChipGen.current() ?? .m5Gen
        return AsyncStream { cont in
            let task = Task {
                while !Task.isCancelled {
                    let r = await readings(for: chip)
                    cont.yield(r)
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                }
                cont.finish()
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
