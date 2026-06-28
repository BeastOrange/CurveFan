import XCTest
@testable import CurveFanCore

final class SMCServiceTests: XCTestCase {
    func testSMCParamStructIsExpectedDriverSize() {
        XCTAssertEqual(SMCService.smcParamStructSize, 80)
    }

    func testSMCUsesAppleSMCDriverSelector() {
        XCTAssertEqual(SMCService.driverSelector, 2)
    }
}
