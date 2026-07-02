import XCTest
@testable import CurveFanCore

final class PresetTests: XCTestCase {
    func testPresetDefaults() {
        let defaults = PresetFactory.defaults
        XCTAssertEqual(defaults.count, 4)
        XCTAssertEqual(defaults[0].name, "Auto")
        XCTAssertEqual(defaults[1].name, "Quiet")
        XCTAssertEqual(defaults[2].name, "Balanced")
        XCTAssertEqual(defaults[3].name, "MaxCool")
    }

    func testDefaultsUseProvidedSensorKey() {
        let defaults = PresetFactory.defaults(maxRPM: 6550, sensorKey: "Tp01")
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
        XCTAssertEqual(quiet.fanToCurve[0]?.points.first?.temperature, 20)
        XCTAssertEqual(quiet.fanToCurve[0]?.points.last?.temperature, 100)
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

    func testCustomPresetCodablePreservesMultipleFans() throws {
        let curve = FanCurve(name: "Shared", points: [
            CurvePoint(temperature: 30, rpm: 1200),
            CurvePoint(temperature: 90, rpm: 6000)
        ], sensorKey: "TC0P")
        let preset = Preset(
            name: "Dual Fan",
            fanToCurve: [0: curve, 1: curve],
            fanToSensor: [0: "TC0P", 1: "TC0P"]
        )

        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(Preset.self, from: data)

        XCTAssertEqual(decoded.fanToCurve.count, 2)
        XCTAssertEqual(decoded.fanToCurve[0]?.points, curve.points)
        XCTAssertEqual(decoded.fanToCurve[1]?.sensorKey, "TC0P")
        XCTAssertEqual(decoded.fanToSensor[1], "TC0P")
    }

    func testPresetStoreLoadAllEmptyDirectoryDoesNotIncludeDefaults() async throws {
        let directory = try makeTemporaryPresetDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PresetStore(presetsDir: directory)
        let loaded = await store.load()

        XCTAssertTrue(loaded.isEmpty)
        XCTAssertEqual(PresetFactory.defaults.count, 4)
    }

    func testPresetStoreSaveAndLoadCustomPreset() async throws {
        let directory = try makeTemporaryPresetDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preset = Preset(name: "Custom", fanToCurve: [
            0: FanCurve(points: [
                CurvePoint(temperature: 30, rpm: 1200),
                CurvePoint(temperature: 90, rpm: 6000)
            ], sensorKey: "TC0P")
        ], fanToSensor: [0: "TC0P"])

        let store = PresetStore(presetsDir: directory)
        try await store.save(preset)
        let reloaded = PresetStore(presetsDir: directory)
        let loaded = await reloaded.load()

        XCTAssertEqual(loaded, [preset])
    }

    func testPresetStoreDeleteRemovesPreset() async throws {
        let directory = try makeTemporaryPresetDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preset = Preset(name: "ToDelete", fanToCurve: [
            0: FanCurve(points: [
                CurvePoint(temperature: 30, rpm: 1200),
                CurvePoint(temperature: 90, rpm: 6000)
            ], sensorKey: "TC0P")
        ], fanToSensor: [0: "TC0P"])

        let store = PresetStore(presetsDir: directory)
        try await store.save(preset)
        try await store.delete(id: preset.id)
        let loaded = await store.load()

        XCTAssertTrue(loaded.isEmpty)
    }

    func testPresetIdsAreUnique() {
        let a = Preset(name: "A")
        let b = Preset(name: "B")
        XCTAssertNotEqual(a.id, b.id)
    }

    private func makeTemporaryPresetDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CurveFanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
