import XCTest
@testable import CurveFanCore

final class IPCProtocolTests: XCTestCase {
    func testIPCCommandCodable() throws {
        let cmd = IPCCommand.readKey(key: "FNum")
        let data = try JSONEncoder().encode(cmd)
        let decoded = try JSONDecoder().decode(IPCCommand.self, from: data)
        if case .readKey(let key) = decoded {
            XCTAssertEqual(key, "FNum")
        } else {
            XCTFail("Expected readKey command")
        }
    }

    func testIPCReadKeyDataCommandCodable() throws {
        let cmd = IPCCommand.readKeyData(key: "Tc0P")
        let data = try JSONEncoder().encode(cmd)
        let decoded = try JSONDecoder().decode(IPCCommand.self, from: data)
        if case .readKeyData(let key) = decoded {
            XCTAssertEqual(key, "Tc0P")
        } else {
            XCTFail("Expected readKeyData command")
        }
    }

    func testIPCResponseSuccess() throws {
        let resp = IPCResponse(success: true, value: 42.0, error: nil)
        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.value, 42.0)
        XCTAssertNil(decoded.error)
    }

    func testIPCResponseFailure() throws {
        let resp = IPCResponse(success: false, value: nil, error: "something broke")
        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: data)
        XCTAssertFalse(decoded.success)
        XCTAssertEqual(decoded.error, "something broke")
    }

    func testIPCResponseWithFanInfo() throws {
        let info = FanInfo(fanCount: 2, actualRPM: 3000, minRPM: 1200, maxRPM: 7200, mode: .manual)
        let resp = IPCResponse(success: true, value: nil, fanInfo: info, error: nil)
        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: data)
        XCTAssertEqual(decoded.fanInfo?.actualRPM, 3000)
        XCTAssertEqual(decoded.fanInfo?.mode, .manual)
    }

    func testIPCResponseWithRawSMCData() throws {
        let resp = IPCResponse(success: true, value: nil, data: [0x10, 0x00], dataType: SMCDataType.sp78.rawValue, error: nil)
        let data = try JSONEncoder().encode(resp)
        let decoded = try JSONDecoder().decode(IPCResponse.self, from: data)
        XCTAssertEqual(decoded.data, [0x10, 0x00])
        XCTAssertEqual(decoded.dataType, SMCDataType.sp78.rawValue)
    }
}
