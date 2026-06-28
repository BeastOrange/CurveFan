import Foundation

public enum IPCCommand: Codable {
    case readKey(key: String)
    case readKeyData(key: String)
    case writeFanRPM(fan: Int, rpm: Int)
    case setFanMode(fan: Int, mode: Int)
    case unlockFanControl(fan: Int)
    case restoreFanControl(fan: Int)
    case getFanInfo(fan: Int)
    case ping
}

public struct IPCResponse: Codable, Sendable {
    public let success: Bool
    public let value: Double?
    public let error: String?
    public let fanInfo: FanInfo?
    public let data: [UInt8]?
    public let dataType: UInt32?

    public init(
        success: Bool,
        value: Double?,
        fanInfo: FanInfo? = nil,
        data: [UInt8]? = nil,
        dataType: UInt32? = nil,
        error: String?
    ) {
        self.success = success
        self.value = value
        self.fanInfo = fanInfo
        self.data = data
        self.dataType = dataType
        self.error = error
    }
}

public struct FanInfo: Codable, Sendable {
    public let fanCount: Int
    public let actualRPM: Double
    public let minRPM: Double
    public let maxRPM: Double
    public let mode: FanMode

    public init(fanCount: Int, actualRPM: Double, minRPM: Double, maxRPM: Double, mode: FanMode) {
        self.fanCount = fanCount
        self.actualRPM = actualRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.mode = mode
    }
}
