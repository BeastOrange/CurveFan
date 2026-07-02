// FakeSMC.swift -- In-process SMC stub used when CURVEFAN_HELPER_FAKE_SMC=1.
// Allows IPC testing without hardware access.

import Foundation
import CurveFanCore

enum FakeSMC {
    static let fanCount = 1

    static func readKey(_ key: String) throws -> Double {
        switch key {
        case "FNum": return 1
        case "F0Ac": return 2400
        case "F0Mn": return 1200
        case "F0Mx": return 7200
        case "F0Md", "F0md": return 0
        case "Tc0P": return 42
        default: throw SMCError.keyNotFound(key)
        }
    }

    static func readKeyData(_ key: String) throws -> (bytes: [UInt8], dataType: UInt32) {
        switch key {
        case "FNum":
            return ([1], SMCDataType.ui8.rawValue)
        case "F0Ac", "F0Mn", "F0Mx":
            return (try SMCDecoder.shared.encode(try readKey(key), as: .flt), SMCDataType.flt.rawValue)
        case "F0Md", "F0md":
            return ([0], SMCDataType.ui8.rawValue)
        case "Tc0P":
            return ([0x2A, 0x00], SMCDataType.sp78.rawValue)
        default:
            throw SMCError.keyNotFound(key)
        }
    }

    static func fanInfo(fan: Int) throws -> FanInfo {
        guard fan >= 0 && fan < fanCount else {
            throw SMCError.invalidData("fan index \(fan) is outside 0-\(max(fanCount - 1, 0))")
        }
        return FanInfo(fanCount: fanCount, actualRPM: 2400, minRPM: 1200, maxRPM: 7200, mode: .auto)
    }
}
