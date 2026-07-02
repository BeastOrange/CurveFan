import XCTest
@testable import CurveFanCore

final class PresetIsAutoTests: XCTestCase {
    func testAutoPresetIsAuto() {
        XCTAssertTrue(Preset.auto.isAuto)
    }

    func testNonAutoPresetIsNotAuto() {
        let preset = Preset(id: UUID(), name: "Quiet", fanToCurve: [:], fanToSensor: [:], createdAt: Date())
        XCTAssertFalse(preset.isAuto)
    }
}
