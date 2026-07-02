import XCTest
@testable import CurveFanCore

final class FanModeTests: XCTestCase {
    func testFanModeConformsToProtocol() {
        let mode: any FanControlModeProtocol = FanMode.manual
        XCTAssertEqual(mode.rawValue, 1)
    }
    func testFanModeRawValuesPersist() {
        XCTAssertEqual(FanMode.auto.rawValue, 0)
        XCTAssertEqual(FanMode.manual.rawValue, 1)
        XCTAssertEqual(FanMode.system.rawValue, 3)
    }
}
