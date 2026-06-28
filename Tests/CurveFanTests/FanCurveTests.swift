import XCTest
@testable import CurveFanCore

final class FanCurveTests: XCTestCase {
    func testLinearInterpolation() {
        let curve = FanCurve(points: [
            CurvePoint(temperature: 30, rpm: 1200),
            CurvePoint(temperature: 80, rpm: 5000)
        ])
        let rpm = curve.rpm(for: 55)
        XCTAssertEqual(rpm, 3100)
    }

    func testInterpolationAtLowerBound() {
        let curve = FanCurve(points: [
            CurvePoint(temperature: 30, rpm: 1200),
            CurvePoint(temperature: 80, rpm: 5000)
        ])
        XCTAssertEqual(curve.rpm(for: 20), 1200)
    }

    func testInterpolationAtUpperBound() {
        let curve = FanCurve(points: [
            CurvePoint(temperature: 30, rpm: 1200),
            CurvePoint(temperature: 80, rpm: 5000)
        ])
        XCTAssertEqual(curve.rpm(for: 90), 5000)
    }

    func testEmptyCurveReturnsZero() {
        let curve = FanCurve(points: [])
        XCTAssertEqual(curve.rpm(for: 50), 0)
    }

    func testRPMClamping() {
        let curve = FanCurve(points: [
            CurvePoint(temperature: 0, rpm: 0),
            CurvePoint(temperature: 100, rpm: 10000)
        ])
        let clamped = curve.rpm(for: 50, minRPM: 1000, maxRPM: 5000)
        XCTAssertEqual(clamped, 5000)
    }

    func testRPMClampingLower() {
        let curve = FanCurve(points: [
            CurvePoint(temperature: 0, rpm: 500),
            CurvePoint(temperature: 100, rpm: 500)
        ])
        let clamped = curve.rpm(for: 50, minRPM: 1000, maxRPM: 5000)
        XCTAssertEqual(clamped, 1000)
    }

    func testClampedZeroReturnsZero() {
        let curve = FanCurve(points: [])
        XCTAssertEqual(curve.rpm(for: 50, minRPM: 1000, maxRPM: 5000), 0)
    }

    func testIsValid() {
        let valid = FanCurve(points: [
            CurvePoint(temperature: 20, rpm: 1000),
            CurvePoint(temperature: 40, rpm: 2000)
        ])
        XCTAssertTrue(valid.isValid)
    }

    func testInvalidLessThanTwoPoints() {
        let curve = FanCurve(points: [CurvePoint(temperature: 30, rpm: 1200)])
        XCTAssertFalse(curve.isValid)
    }

    func testInvalidNonAscendingTemperatures() {
        let curve = FanCurve(points: [
            CurvePoint(temperature: 50, rpm: 1200),
            CurvePoint(temperature: 30, rpm: 5000)
        ])
        XCTAssertFalse(curve.isValid)
    }

    func testValidateReturnsErrors() {
        let bad = FanCurve(points: [
            CurvePoint(temperature: 150, rpm: 99999)
        ])
        let errors = bad.validate(rpmRange: 1000...5000)
        XCTAssertFalse(errors.isEmpty)
    }

    func testValidateEmpty() {
        let empty = FanCurve(points: [])
        let errors = empty.validate(rpmRange: 1000...5000)
        XCTAssert(errors.contains { $0.contains("at least 2 points") })
    }

    func testCurveWithMultipleSegments() {
        let curve = FanCurve(points: [
            CurvePoint(temperature: 30, rpm: 1200),
            CurvePoint(temperature: 50, rpm: 2500),
            CurvePoint(temperature: 70, rpm: 4000),
            CurvePoint(temperature: 90, rpm: 6000)
        ])
        XCTAssertEqual(curve.rpm(for: 40), 1850, accuracy: 10)
        XCTAssertEqual(curve.rpm(for: 60), 3250, accuracy: 10)
        XCTAssertEqual(curve.rpm(for: 80), 5000, accuracy: 10)
    }

    func testCurveCodable() throws {
        let curve = FanCurve(name: "Test", points: [
            CurvePoint(temperature: 30, rpm: 1200),
            CurvePoint(temperature: 80, rpm: 5000)
        ])
        let data = try JSONEncoder().encode(curve)
        let decoded = try JSONDecoder().decode(FanCurve.self, from: data)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.points.count, 2)
    }
}
