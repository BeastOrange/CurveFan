import Foundation
import CurveFanCore
import Darwin
import os

private let socketPath = ProcessInfo.processInfo.environment["CURVEFAN_SOCKET_PATH"] ?? "/var/run/curvefan-helper.socket"
private let encoder = JSONEncoder()
private let decoder = JSONDecoder()
private let smc = SMCService.shared
private let fakeSMC = ProcessInfo.processInfo.environment["CURVEFAN_HELPER_FAKE_SMC"] == "1"

signal(SIGTERM) { _ in cleanup(); exit(0) }
signal(SIGINT) { _ in cleanup(); exit(0) }

func cleanup() {
    unlink(socketPath)
    do {
        try smc.open()
        defer { try? smc.close() }
        let fanCount = try currentFanCount()
        for fan in 0..<fanCount {
            do {
                try restoreFanControl(fan: fan)
            } catch {
                os_log(.error, "restore failed for fan %{public}d: %{public}@", fan, error.localizedDescription)
            }
        }
    } catch {
        os_log(.error, "cleanup failed: %{public}@", error.localizedDescription)
    }
}

func handleCommand(_ json: Data) -> Data {
    guard let cmd = try? decoder.decode(IPCCommand.self, from: json) else {
        return response(success: false, error: "invalid command")
    }

    do {
        switch cmd {
        case .readKey(let key):
            let value = try readKey(key)
            return response(success: true, value: value)
        case .readKeyData(let key):
            let payload = try readKeyData(key)
            return response(success: true, data: payload.bytes, dataType: payload.dataType)
        case .readKeysData(let keys):
            var batch: [String: SMCKeyData] = [:]
            for key in keys {
                guard let payload = try? readKeyData(key) else { continue }
                batch[key] = SMCKeyData(data: payload.bytes, dataType: payload.dataType)
            }
            return response(success: true, batch: batch)
        case .writeFanRPM(let fan, let rpm):
            try writeFanRPM(fan: fan, rpm: rpm)
            return response(success: true)
        case .setFanMode(let fan, let mode):
            try setFanMode(fan: fan, mode: mode)
            return response(success: true)
        case .unlockFanControl(let fan):
            try unlockFanControl(fan: fan)
            return response(success: true)
        case .restoreFanControl(let fan):
            try restoreFanControl(fan: fan)
            return response(success: true)
        case .getFanInfo(let fan):
            let info = try getFanInfo(fan: fan)
            return response(success: true, fanInfo: info)
        case .ping:
            return response(success: true)
        }
    } catch {
        os_log(.error, "command failed: %{public}@", error.localizedDescription)
        return response(success: false, error: error.localizedDescription)
    }
}

func response(
    success: Bool,
    value: Double? = nil,
    fanInfo: FanInfo? = nil,
    data: [UInt8]? = nil,
    dataType: UInt32? = nil,
    batch: [String: SMCKeyData]? = nil,
    error: String? = nil
) -> Data {
    let payload = IPCResponse(
        success: success,
        value: value,
        fanInfo: fanInfo,
        data: data,
        dataType: dataType,
        batch: batch,
        error: error
    )
    return (try? encoder.encode(payload)) ?? Data()
}

if fakeSMC {
    os_log(.info, "CurveFanHelper daemon started in fake SMC mode")
} else {
    try smc.open()
    os_log(.info, "CurveFanHelper daemon started, SMC connected")
}

func readKey(_ key: String) throws -> Double {
    if fakeSMC {
        return try fakeReadKey(key)
    }
    let payload = try readKeyData(key)
    return try SMCDecoder.shared.decode(rawValue: payload.dataType, bytes: payload.bytes)
}

func readKeyData(_ key: String) throws -> (bytes: [UInt8], dataType: UInt32) {
    try validateSMCKey(key)
    if fakeSMC {
        return try fakeReadKeyData(key)
    }
    let bytes = try smc.readData(key)
    let info = try smc.keyInfo(key)
    return (bytes, info.dataType)
}

func writeFanRPM(fan: Int, rpm: Int) throws {
    if fakeSMC {
        try validateFanIndex(fan)
        guard (1200...7200).contains(rpm) else {
            throw SMCError.invalidData("RPM \(rpm) is outside 1200-7200")
        }
        return
    }
    let info = try getFanInfo(fan: fan)
    let clamped = max(Int(info.minRPM), min(Int(info.maxRPM), rpm))
    guard clamped == rpm else {
        throw SMCError.invalidData("RPM \(rpm) is outside \(Int(info.minRPM))-\(Int(info.maxRPM))")
    }
    let bytes = try SMCDecoder.shared.encode(Double(rpm), as: .flt)
    try smc.writeData(String(format: "F%dTg", fan), bytes: bytes)
}

func setFanMode(fan: Int, mode: Int) throws {
    try validateFanIndex(fan)
    guard FanMode(rawValue: mode) != nil else {
        throw SMCError.invalidData("unsupported fan mode \(mode)")
    }
    if fakeSMC { return }
    let key = try modeKey(for: fan)
    try smc.writeData(key, bytes: SMCDecoder.shared.encode(Double(mode), as: .ui8))
}

func unlockFanControl(fan: Int) throws {
    try validateFanIndex(fan)
    if fakeSMC { return }
    let chip = ChipGen.current() ?? .m5Gen
    if chip == .m5Gen {
        try setFanMode(fan: fan, mode: FanMode.manual.rawValue)
        return
    }

    try smc.writeData("Ftst", bytes: try SMCDecoder.shared.encode(1, as: .ui8))
    for _ in 0..<100 {
        let bytes = try smc.readData(try modeKey(for: fan))
        if Int(try SMCDecoder.shared.decode(type: .ui8, bytes: bytes)) != FanMode.system.rawValue {
            break
        }
        usleep(100_000)
    }
    try setFanMode(fan: fan, mode: FanMode.manual.rawValue)
}

func restoreFanControl(fan: Int) throws {
    if fakeSMC {
        try validateFanIndex(fan)
        return
    }
    try setFanMode(fan: fan, mode: FanMode.auto.rawValue)
    if ChipGen.current() != .m5Gen {
        try smc.writeData("Ftst", bytes: SMCDecoder.shared.encode(0, as: .ui8))
    }
}

func getFanInfo(fan: Int) throws -> FanInfo {
    if fakeSMC {
        try validateFanIndex(fan, fanCount: 1)
        return FanInfo(fanCount: 1, actualRPM: 2400, minRPM: 1200, maxRPM: 7200, mode: .auto)
    }
    let fanCount = try currentFanCount()
    try validateFanIndex(fan, fanCount: fanCount)
    let actual = try readKey(String(format: "F%dAc", fan))
    let minimum = try readKey(String(format: "F%dMn", fan))
    let maximum = try readKey(String(format: "F%dMx", fan))
    let modeBytes = try smc.readData(try modeKey(for: fan))
    let modeValue = Int(try SMCDecoder.shared.decode(type: .ui8, bytes: modeBytes))
    return FanInfo(
        fanCount: fanCount,
        actualRPM: actual,
        minRPM: minimum,
        maxRPM: maximum,
        mode: FanMode(rawValue: modeValue) ?? .auto
    )
}

func currentFanCount() throws -> Int {
    if fakeSMC { return 1 }
    let bytes = try smc.readData("FNum")
    guard let first = bytes.first else { throw SMCError.invalidData("FNum returned no data") }
    return Int(first)
}

func validateFanIndex(_ fan: Int, fanCount: Int? = nil) throws {
    let count = try fanCount ?? currentFanCount()
    guard fan >= 0 && fan < count else {
        throw SMCError.invalidData("fan index \(fan) is outside 0-\(max(count - 1, 0))")
    }
}

func validateSMCKey(_ key: String) throws {
    let bytes = Array(key.utf8)
    guard (1...4).contains(bytes.count) else {
        throw SMCError.invalidData("SMC keys must be 1-4 bytes")
    }
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else {
        throw SMCError.invalidData("SMC keys must be printable ASCII")
    }
}

func modeKey(for fan: Int) throws -> String {
    let chip = ChipGen.current() ?? .m5Gen
    let preferred = SMCKeyDB.writableFanModeKey(for: fan, chip: chip) ?? String(format: "F%dMd", fan)
    let fallback = preferred.contains("md") ? String(format: "F%dMd", fan) : String(format: "F%dmd", fan)

    for key in [preferred, fallback] {
        do {
            _ = try smc.keyInfo(key)
            return key
        } catch {
            continue
        }
    }
    throw SMCError.keyNotFound("fan \(fan) mode key")
}

func fakeReadKey(_ key: String) throws -> Double {
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

func fakeReadKeyData(_ key: String) throws -> (bytes: [UInt8], dataType: UInt32) {
    switch key {
    case "FNum":
        return ([1], SMCDataType.ui8.rawValue)
    case "F0Ac", "F0Mn", "F0Mx":
        return (try SMCDecoder.shared.encode(try fakeReadKey(key), as: .flt), SMCDataType.flt.rawValue)
    case "F0Md", "F0md":
        return ([0], SMCDataType.ui8.rawValue)
    case "Tc0P":
        return ([0x2A, 0x00], SMCDataType.sp78.rawValue)
    default:
        throw SMCError.keyNotFound(key)
    }
}

unlink(socketPath)
let sock = socket(AF_UNIX, SOCK_STREAM, 0)
guard sock >= 0 else { fatalError("socket() failed") }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let socketPathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
withUnsafeMutablePointer(to: &addr.sun_path) { pointer in
    pointer.withMemoryRebound(to: Int8.self, capacity: socketPathCapacity) { buffer in
        _ = socketPath.withCString { path in
            strncpy(buffer, path, socketPathCapacity - 1)
        }
    }
}

let addrLength = socklen_t(MemoryLayout<sockaddr_un>.size)
let bindResult = withUnsafePointer(to: &addr) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.bind(sock, sockaddrPointer, addrLength)
    }
}
guard bindResult == 0 else {
    fatalError("bind() failed: \(String(cString: strerror(errno)))")
}

configureSocketPermissions(socketPath)
guard listen(sock, 5) == 0 else { fatalError("listen() failed") }
os_log(.info, "listening on %{public}@", socketPath)

while true {
    let client = accept(sock, nil, nil)
    guard client >= 0 else { continue }
    DispatchQueue.global().async {
        defer { close(client) }
        guard isAuthorizedPeer(client) else {
            os_log(.error, "rejected unauthorized IPC peer")
            return
        }
        do {
            let request = try receiveFrame(socket: client)
            try sendFrame(handleCommand(request), socket: client)
        } catch {
            os_log(.error, "IPC error: %{public}@", error.localizedDescription)
        }
    }
}

func configureSocketPermissions(_ path: String) {
    let consoleUID = currentConsoleUID()
    if consoleUID != 0 {
        chown(path, uid_t(consoleUID), getgid())
        chmod(path, 0o600)
    } else {
        chmod(path, 0o660)
    }
}

@Sendable func isAuthorizedPeer(_ socket: Int32) -> Bool {
    var peer = xucred()
    var size = socklen_t(MemoryLayout<xucred>.stride)
    let result = withUnsafeMutablePointer(to: &peer) { pointer in
        pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<xucred>.stride) { raw in
            getsockopt(socket, SOL_LOCAL, LOCAL_PEERCRED, raw, &size)
        }
    }
    guard result == 0 else { return false }
    let uid = uid_t(peer.cr_uid)
    return uid == 0 || uid == geteuid() || uid == currentConsoleUID()
}

@Sendable func currentConsoleUID() -> uid_t {
    guard let output = try? shellOutput(["/usr/bin/stat", "-f", "%u", "/dev/console"]),
          let uid = uid_t(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return 0
    }
    return uid
}

@Sendable func shellOutput(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: arguments[0])
    process.arguments = Array(arguments.dropFirst())
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    process.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

@Sendable func sendFrame(_ data: Data, socket: Int32) throws {
    let frame = try IPCFraming.encode(data)
    try frame.withUnsafeBytes { raw in
        try sendAll(raw, socket: socket)
    }
}

@Sendable func receiveFrame(socket: Int32) throws -> Data {
    var header = [UInt8](repeating: 0, count: 4)
    try readAll(into: &header, socket: socket)
    let length = try IPCFraming.decodeLength(header)
    var payload = [UInt8](repeating: 0, count: length)
    try readAll(into: &payload, socket: socket)
    return Data(payload)
}

@Sendable func sendAll(_ bytes: UnsafeRawBufferPointer, socket: Int32) throws {
    guard let base = bytes.baseAddress else { return }
    var sent = 0
    while sent < bytes.count {
        let n = send(socket, base.advanced(by: sent), bytes.count - sent, 0)
        guard n > 0 else { throw SMCError.invalidData("short IPC write") }
        sent += n
    }
}

@Sendable func readAll(into buffer: inout [UInt8], socket: Int32) throws {
    var received = 0
    while received < buffer.count {
        let remaining = buffer.count - received
        let n = buffer.withUnsafeMutableBytes { raw in
            recv(socket, raw.baseAddress!.advanced(by: received), remaining, 0)
        }
        guard n > 0 else { throw SMCError.invalidData("short IPC read") }
        received += n
    }
}
