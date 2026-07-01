import XCTest
@testable import CurveFanCore

final class ConnectionStatusTests: XCTestCase {
    func testIsConnectedReturnsTrueForConnected() {
        XCTAssertTrue(ConnectionStatus.connected.isConnected)
    }
    func testIsConnectedReturnsFalseForDisconnected() {
        XCTAssertFalse(ConnectionStatus.disconnected.isConnected)
    }
    func testIsConnectedReturnsFalseForError() {
        XCTAssertFalse(ConnectionStatus.error("boom").isConnected)
    }
}
