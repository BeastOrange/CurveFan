import Foundation

public struct CurvePoint: Codable, Equatable, Sendable {
    public var temperature: Double
    public var rpm: Int

    public init(temperature: Double, rpm: Int) {
        self.temperature = temperature
        self.rpm = rpm
    }
}

public struct FanCurve: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var points: [CurvePoint]
    public var sensorKey: String

    public init(id: UUID = UUID(), name: String = "", points: [CurvePoint] = [], sensorKey: String = "") {
        self.id = id
        self.name = name
        self.points = points
        self.sensorKey = sensorKey
    }

    public var isValid: Bool {
        guard points.count >= 2 else { return false }
        for i in 1..<points.count {
            if points[i].temperature <= points[i - 1].temperature { return false }
            if points[i].rpm < points[i - 1].rpm { return false }
        }
        return true
    }

    public var isEmpty: Bool { points.isEmpty }

    public func rpm(for temperature: Double) -> Int {
        guard !points.isEmpty else { return 0 }
        if temperature <= points[0].temperature { return points[0].rpm }
        if temperature >= points.last!.temperature { return points.last!.rpm }

        for i in 0..<(points.count - 1) {
            let a = points[i]
            let b = points[i + 1]
            if temperature >= a.temperature && temperature <= b.temperature {
                return Int(Self.monotoneCubicValue(points: points, segmentIndex: i, temperature: temperature).rounded())
            }
        }
        return points.last!.rpm
    }

    public func rpm(for temperature: Double, minRPM: Int, maxRPM: Int) -> Int {
        let computed = rpm(for: temperature)
        if computed == 0 { return 0 }
        return max(minRPM, min(maxRPM, computed))
    }

    public static func rateLimitedRPM(
        current: Int,
        target: Int,
        interval: TimeInterval,
        maxRPMChangePerSecond: Int
    ) -> Int {
        let delta = target - current
        let maxChange = max(1, Int((Double(maxRPMChangePerSecond) * interval).rounded()))
        if abs(delta) <= maxChange { return target }
        return current + (delta > 0 ? maxChange : -maxChange)
    }

    public static func rateLimitedTemperature(
        current: Double,
        target: Double,
        interval: TimeInterval,
        maxChangePerSecond: Double
    ) -> Double {
        let delta = target - current
        let maxChange = max(0.001, maxChangePerSecond * interval)
        if abs(delta) <= maxChange { return target }
        return current + (delta > 0 ? maxChange : -maxChange)
    }

    public func validate(rpmRange: ClosedRange<Int>) -> [String] {
        var errors: [String] = []
        if points.count < 2 {
            errors.append("Curve needs at least 2 points")
            return errors
        }
        for i in 1..<points.count {
            if points[i].temperature <= points[i - 1].temperature {
                errors.append("Points must be in ascending temperature order")
                break
            }
            if points[i].rpm < points[i - 1].rpm {
                errors.append("RPM must not decrease as temperature rises")
                break
            }
        }
        for (i, point) in points.enumerated() {
            if point.temperature < 0 || point.temperature > 100 {
                errors.append("Point \(i): temperature \(point.temperature)°C is out of range (0-100)")
            }
            if !rpmRange.contains(point.rpm) {
                errors.append("Point \(i): RPM \(point.rpm) is out of range (\(rpmRange.lowerBound)-\(rpmRange.upperBound))")
            }
        }
        return errors
    }

    private static func monotoneCubicValue(points: [CurvePoint], segmentIndex: Int, temperature: Double) -> Double {
        let x = points.map(\.temperature)
        let y = points.map { Double($0.rpm) }
        let slopes = monotoneTangents(x: x, y: y)
        let h = x[segmentIndex + 1] - x[segmentIndex]
        guard h > 0 else { return y[segmentIndex] }
        let t = (temperature - x[segmentIndex]) / h
        let t2 = t * t
        let t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2
        return h00 * y[segmentIndex]
            + h10 * h * slopes[segmentIndex]
            + h01 * y[segmentIndex + 1]
            + h11 * h * slopes[segmentIndex + 1]
    }

    private static func monotoneTangents(x: [Double], y: [Double]) -> [Double] {
        guard x.count > 2 else {
            let slope = x.count == 2 ? (y[1] - y[0]) / (x[1] - x[0]) : 0
            return Array(repeating: slope, count: x.count)
        }
        let delta = (0..<(x.count - 1)).map { index in
            (y[index + 1] - y[index]) / (x[index + 1] - x[index])
        }
        var tangents = Array(repeating: 0.0, count: x.count)
        tangents[0] = delta[0]
        tangents[x.count - 1] = delta[delta.count - 1]
        for index in 1..<(x.count - 1) {
            tangents[index] = (delta[index - 1] + delta[index]) / 2
        }
        for index in 0..<delta.count where delta[index] == 0 {
            tangents[index] = 0
            tangents[index + 1] = 0
        }
        for index in 0..<delta.count where delta[index] != 0 {
            let a = tangents[index] / delta[index]
            let b = tangents[index + 1] / delta[index]
            let length = hypot(a, b)
            if length > 3 {
                let scale = 3 / length
                tangents[index] = scale * a * delta[index]
                tangents[index + 1] = scale * b * delta[index]
            }
        }
        return tangents
    }
}

public struct Preset: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var fanToCurve: [Int: FanCurve]
    public var fanToSensor: [Int: String]
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, fanToCurve: [Int: FanCurve] = [:], fanToSensor: [Int: String] = [:], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.fanToCurve = fanToCurve
        self.fanToSensor = fanToSensor
        self.createdAt = createdAt
    }

    public var isAuto: Bool { name == "Auto" }

    public static let auto = Preset(name: "Auto", fanToCurve: [:], fanToSensor: [:])

    private enum DefaultRPM {
        static let quietLow = 1200
        static let quietMid = 2500
        static let balancedLow = 1200
        static let balancedMid = 2000
        static let balancedHigh = 3500
    }

    public static func quiet(maxRPM: Int) -> Preset {
        quiet(maxRPM: maxRPM, sensorKey: "")
    }

    public static func quiet(maxRPM: Int, sensorKey: String) -> Preset {
        let curve = FanCurve(name: "Quiet", points: [
            CurvePoint(temperature: 20, rpm: DefaultRPM.quietLow),
            CurvePoint(temperature: 45, rpm: DefaultRPM.quietLow),
            CurvePoint(temperature: 70, rpm: DefaultRPM.quietMid),
            CurvePoint(temperature: 100, rpm: maxRPM)
        ], sensorKey: sensorKey)
        return Preset(name: "Quiet", fanToCurve: [0: curve], fanToSensor: sensorKey.isEmpty ? [:] : [0: sensorKey])
    }

    public static func balanced(maxRPM: Int) -> Preset {
        balanced(maxRPM: maxRPM, sensorKey: "")
    }

    public static func balanced(maxRPM: Int, sensorKey: String) -> Preset {
        let curve = FanCurve(name: "Balanced", points: [
            CurvePoint(temperature: 20, rpm: DefaultRPM.balancedLow),
            CurvePoint(temperature: 50, rpm: DefaultRPM.balancedMid),
            CurvePoint(temperature: 70, rpm: DefaultRPM.balancedHigh),
            CurvePoint(temperature: 100, rpm: maxRPM)
        ], sensorKey: sensorKey)
        return Preset(name: "Balanced", fanToCurve: [0: curve], fanToSensor: sensorKey.isEmpty ? [:] : [0: sensorKey])
    }

    public static func maxCool(maxRPM: Int) -> Preset {
        maxCool(maxRPM: maxRPM, sensorKey: "")
    }

    public static func maxCool(maxRPM: Int, sensorKey: String) -> Preset {
        let curve = FanCurve(name: "MaxCool", points: [
            CurvePoint(temperature: 20, rpm: maxRPM / 2),
            CurvePoint(temperature: 35, rpm: maxRPM)
        ], sensorKey: sensorKey)
        return Preset(name: "MaxCool", fanToCurve: [0: curve], fanToSensor: sensorKey.isEmpty ? [:] : [0: sensorKey])
    }
}
