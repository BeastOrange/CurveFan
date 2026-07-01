import XCTest
@testable import CurveFanCore

final class IPCSerializerEnvelopeTests: XCTestCase {
    func testEncodeProducesV1EnvelopeWithCommand() throws {
        let data = try IPCSerializer.encode(.readKey(key: "FNum"))
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(envelope?["v"] as? Int, 1)
        let cmd = envelope?["cmd"]
        XCTAssertNotNil(cmd)
        let cmdData = try JSONSerialization.data(withJSONObject: cmd as Any)
        let cmdObject = try JSONSerialization.jsonObject(with: cmdData) as? [String: Any]
        XCTAssertNotNil(cmdObject?["readKey"])
    }

    func testDecodeRequestAcceptsV1Envelope() throws {
        let envelope: [String: Any] = ["v": 1, "cmd": ["ping": [:]]]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        let payload = try IPCSerializer.decodeRequest(data)
        if case .ping = payload.command {
            XCTAssertEqual(payload.version, 1)
        } else {
            XCTFail("Expected ping command")
        }
    }

    func testIsCompatibleVersionAcceptsLegacyAndV1Only() {
        XCTAssertTrue(IPCSerializer.isCompatibleVersion(0), "legacy raw-IPCCommand wire format (version 0) must stay dispatchable")
        XCTAssertTrue(IPCSerializer.isCompatibleVersion(1), "current v1 envelope must be dispatchable")
        XCTAssertFalse(IPCSerializer.isCompatibleVersion(2), "future v2 must be rejected until this build opts in")
        XCTAssertFalse(IPCSerializer.isCompatibleVersion(999), "unknown future versions must be rejected")
    }

    func testDecodeRequestAcceptsLegacyRawIPCCommand() throws {
        let rawData = #"{"ping":{}}"#.data(using: .utf8)!
        let payload = try IPCSerializer.decodeRequest(rawData)
        if case .ping = payload.command {
            XCTAssertEqual(payload.version, 0)
        } else {
            XCTFail("Expected ping command")
        }
    }

    func testDecodeResponseRoundTrip() throws {
        let resp = IPCResponse(success: true, value: 42.0, error: nil)
        let data = try JSONEncoder().encode(resp)
        let decoded = try IPCSerializer.decode(data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.value, 42.0)
    }
}