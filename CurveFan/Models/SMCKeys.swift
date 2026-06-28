import Foundation

public struct SMCKeyDefinition: Codable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let group: SensorGroup
    public let type: SMCDataType
    public let writable: Bool
    public let platforms: [ChipGen]
}

/// Queryable database of known SMC keys for Apple Silicon
public enum SMCKeyDB {
    public static let all: [SMCKeyDefinition] = { fanKeys + temperatureKeys }()

    public static let fanKeys: [SMCKeyDefinition] = [
        SMCKeyDefinition(key: "FNum", name: "Fan Count", group: .fan, type: .ui8, writable: false, platforms: ChipGen.allCases),
        SMCKeyDefinition(key: "F0Ac", name: "Fan 0 Actual RPM", group: .fan, type: .flt, writable: false, platforms: ChipGen.allCases),
        SMCKeyDefinition(key: "F0Mn", name: "Fan 0 Minimum RPM", group: .fan, type: .flt, writable: false, platforms: ChipGen.allCases),
        SMCKeyDefinition(key: "F0Mx", name: "Fan 0 Maximum RPM", group: .fan, type: .flt, writable: false, platforms: ChipGen.allCases),
        SMCKeyDefinition(key: "F0Tg", name: "Fan 0 Target RPM", group: .fan, type: .flt, writable: true, platforms: ChipGen.allCases),
        SMCKeyDefinition(key: "F0Md", name: "Fan 0 Mode (M1-M4)", group: .fan, type: .ui8, writable: true, platforms: [.m1Gen, .m2Gen, .m3Gen, .m4Gen]),
        SMCKeyDefinition(key: "F0md", name: "Fan 0 Mode (M5)", group: .fan, type: .ui8, writable: true, platforms: [.m5Gen]),
        SMCKeyDefinition(key: "F1Ac", name: "Fan 1 Actual RPM", group: .fan, type: .flt, writable: false, platforms: ChipGen.allCases),
        SMCKeyDefinition(key: "F1Mn", name: "Fan 1 Minimum RPM", group: .fan, type: .flt, writable: false, platforms: ChipGen.allCases),
        SMCKeyDefinition(key: "F1Mx", name: "Fan 1 Maximum RPM", group: .fan, type: .flt, writable: false, platforms: ChipGen.allCases),
        SMCKeyDefinition(key: "F1Tg", name: "Fan 1 Target RPM", group: .fan, type: .flt, writable: true, platforms: ChipGen.allCases),
        SMCKeyDefinition(key: "F1Md", name: "Fan 1 Mode (M1-M4)", group: .fan, type: .ui8, writable: true, platforms: [.m1Gen, .m2Gen, .m3Gen, .m4Gen]),
        SMCKeyDefinition(key: "F1md", name: "Fan 1 Mode (M5)", group: .fan, type: .ui8, writable: true, platforms: [.m5Gen]),
        SMCKeyDefinition(key: "Ftst", name: "Force Test / Diagnostic Unlock", group: .fan, type: .ui8, writable: true, platforms: [.m1Gen, .m2Gen, .m3Gen, .m4Gen]),
    ]

    public static let temperatureKeys: [SMCKeyDefinition] = {
        var keys: [SMCKeyDefinition] = []
        keys.append(contentsOf: m1m2TempKeys)
        keys.append(contentsOf: m3TempKeys)
        keys.append(contentsOf: m4m5TempKeys)
        return keys
    }()

    private static let m1m2TempKeys: [SMCKeyDefinition] = {
        let pCoreCount = 10
        let eCoreCount = 4
        var keys: [SMCKeyDefinition] = []
        for i in 0..<pCoreCount {
            keys.append(SMCKeyDefinition(key: String(format: "Tp%02d", i), name: "CPU P-core \(i)", group: .cpu, type: .sp78, writable: false, platforms: [.m1Gen, .m2Gen]))
        }
        for i in 0..<eCoreCount {
            keys.append(SMCKeyDefinition(key: String(format: "Te%02d", i), name: "CPU E-core \(i)", group: .cpu, type: .sp78, writable: false, platforms: [.m1Gen, .m2Gen]))
        }
        keys.append(SMCKeyDefinition(key: "Tc0P", name: "CPU Proximity", group: .cpu, type: .sp78, writable: false, platforms: [.m1Gen, .m2Gen, .m3Gen, .m4Gen, .m5Gen]))
        keys.append(SMCKeyDefinition(key: "Tg0P", name: "GPU 0 Temperature", group: .gpu, type: .sp78, writable: false, platforms: ChipGen.allCases))
        keys.append(SMCKeyDefinition(key: "Tg0f", name: "GPU 0 Die", group: .gpu, type: .sp78, writable: false, platforms: [.m1Gen, .m2Gen]))
        keys.append(SMCKeyDefinition(key: "Tm0P", name: "Memory 0 Temperature", group: .memory, type: .sp78, writable: false, platforms: ChipGen.allCases))
        return keys
    }()

    private static let m3TempKeys: [SMCKeyDefinition] = {
        var keys: [SMCKeyDefinition] = []
        let pCoreLabels = ["Tp01", "Tp02", "Tp03", "Tp04", "Tp05", "Tp06", "Tp07", "Tp08",
                           "Tp09", "Tp0A", "Tp0B", "Tp0C", "Tp0D", "Tp0E", "Tp0F", "Tp0G", "Tp0H"]
        for (i, key) in pCoreLabels.enumerated() {
            keys.append(SMCKeyDefinition(key: key, name: "CPU P-core \(i)", group: .cpu, type: .sp78, writable: false, platforms: [.m3Gen]))
        }
        let eCoreLabels = ["Tp0a", "Tp0b", "Tp0c", "Tp0d", "Tp0e", "Tp0f"]
        for (i, key) in eCoreLabels.enumerated() {
            keys.append(SMCKeyDefinition(key: key, name: "CPU E-core \(i)", group: .cpu, type: .sp78, writable: false, platforms: [.m3Gen]))
        }
        keys.append(SMCKeyDefinition(key: "Tg0D", name: "GPU 0 Die", group: .gpu, type: .sp78, writable: false, platforms: [.m3Gen, .m4Gen, .m5Gen]))
        keys.append(SMCKeyDefinition(key: "Tg0j", name: "GPU 0 Junction", group: .gpu, type: .sp78, writable: false, platforms: [.m3Gen, .m4Gen, .m5Gen]))
        return keys
    }()

    private static let m4m5TempKeys: [SMCKeyDefinition] = {
        var keys: [SMCKeyDefinition] = []
        let eOffset = 1 // Tp01-Tp0C for E-cores
        let pOffset = 13 // Tp0D-Tp0Z for P-cores
        for i in 0..<12 {
            keys.append(SMCKeyDefinition(key: String(format: "Tp%02d", eOffset + i), name: "CPU E-core \(i)", group: .cpu, type: .sp78, writable: false, platforms: [.m4Gen, .m5Gen]))
        }
        for i in 0..<14 {
            keys.append(SMCKeyDefinition(key: String(format: "Tp%02d", pOffset + i), name: "CPU P-core \(i)", group: .cpu, type: .sp78, writable: false, platforms: [.m4Gen, .m5Gen]))
        }
        keys.append(SMCKeyDefinition(key: "Tm1P", name: "Memory 1 Temperature", group: .memory, type: .sp78, writable: false, platforms: [.m4Gen, .m5Gen]))
        keys.append(SMCKeyDefinition(key: "TaLP", name: "Airflow Left", group: .system, type: .sp78, writable: false, platforms: [.m4Gen, .m5Gen]))
        keys.append(SMCKeyDefinition(key: "TaRF", name: "Airflow Right", group: .system, type: .sp78, writable: false, platforms: [.m4Gen, .m5Gen]))
        return keys
    }()

    public static func keys(for chip: ChipGen) -> [SMCKeyDefinition] {
        all.filter { $0.platforms.contains(chip) }
    }

    public static func keys(for group: SensorGroup, chip: ChipGen) -> [SMCKeyDefinition] {
        keys(for: chip).filter { $0.group == group }
    }

    public static func definition(for key: String) -> SMCKeyDefinition? {
        all.first { $0.key == key }
    }

    public static func writableFanModeKey(for fan: Int, chip: ChipGen) -> String? {
        let candidates: [String]
        switch chip {
        case .m5Gen:
            candidates = [String(format: "F%dmd", fan), String(format: "F%dMd", fan)]
        default:
            candidates = [String(format: "F%dMd", fan), String(format: "F%dmd", fan)]
        }
        return candidates.first
    }
}
