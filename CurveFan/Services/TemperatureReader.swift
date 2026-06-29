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
        let defs = SMCKeyDB.keys(for: .cpu, chip: chip) +
                   SMCKeyDB.keys(for: .gpu, chip: chip) +
                   SMCKeyDB.keys(for: .memory, chip: chip) +
                   SMCKeyDB.keys(for: .system, chip: chip)

        // Attempt batch read; fall back to per-key reads if the helper doesn't support it.
        let batch: [String: SMCKeyData]
        if let result = await batchRead(keys: defs.map(\.key)) {
            batch = result
        } else {
            return await legacyReadings(defs: defs)
        }

        let now = Date()
        // Iterate `defs` (not the dictionary) to keep deterministic ordering.
        return defs.compactMap { def -> TemperatureReading? in
            guard let raw = batch[def.key] else { return nil }
            guard let value = try? SMCDecoder.shared.decode(rawValue: raw.dataType, bytes: raw.data) else {
                NSLog("CurveFan temperature decode failed for \(def.key)")
                return nil
            }
            return TemperatureReading(key: def.key, name: def.name, group: def.group, value: value, timestamp: now)
        }
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

    private func batchRead(keys: [String]) async -> [String: SMCKeyData]? {
        guard let resp = try? await ipc.send(.readKeysData(keys: keys)),
              resp.success, let batch = resp.batch else { return nil }
        return batch
    }

    private func legacyReadings(defs: [SMCKeyDefinition]) async -> [TemperatureReading] {
        let now = Date()
        var results: [TemperatureReading] = []
        for def in defs {
            guard let resp = try? await ipc.send(.readKeyData(key: def.key)),
                  resp.success, let bytes = resp.data, let dataType = resp.dataType,
                  let value = try? SMCDecoder.shared.decode(rawValue: dataType, bytes: bytes) else { continue }
            results.append(TemperatureReading(key: def.key, name: def.name, group: def.group, value: value, timestamp: now))
        }
        return results
    }
}
