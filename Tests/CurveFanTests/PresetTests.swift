import XCTest
@testable import CurveFanCore

final class PresetTests: XCTestCase {
    func testPresetDefaults() {
        let defaults = PresetManager.shared.defaults
        XCTAssertEqual(defaults.count, 4)
        XCTAssertEqual(defaults[0].name, "Auto")
        XCTAssertEqual(defaults[1].name, "Quiet")
        XCTAssertEqual(defaults[2].name, "Balanced")
        XCTAssertEqual(defaults[3].name, "MaxCool")
    }

    func testDefaultsUseProvidedSensorKey() {
        let defaults = PresetManager.shared.defaults(maxRPM: 6550, sensorKey: "Tp01")
        for preset in defaults.dropFirst() {
            XCTAssertEqual(preset.fanToSensor[0], "Tp01")
            XCTAssertEqual(preset.fanToCurve[0]?.sensorKey, "Tp01")
        }
    }

    func testAutoPresetHasNoCurves() {
        let auto = Preset.auto
        XCTAssertTrue(auto.fanToCurve.isEmpty)
    }

    func testQuietPresetHasCurve() {
        let quiet = Preset.quiet(maxRPM: 5000)
        XCTAssertNotNil(quiet.fanToCurve[0])
        XCTAssertEqual(quiet.fanToCurve[0]?.points.count, 4)
    }

    func testPresetCodable() throws {
        let preset = Preset(name: "Test", fanToCurve: [
            0: FanCurve(name: "TestCurve", points: [
                CurvePoint(temperature: 30, rpm: 1000),
                CurvePoint(temperature: 80, rpm: 5000)
            ])
        ], fanToSensor: [0: "Tp01"])

        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.fanToCurve.count, 1)
        XCTAssertEqual(decoded.fanToSensor[0], "Tp01")
    }

    func testPresetIdsAreUnique() {
        let a = Preset(name: "A")
        let b = Preset(name: "B")
        XCTAssertNotEqual(a.id, b.id)
    }
}
