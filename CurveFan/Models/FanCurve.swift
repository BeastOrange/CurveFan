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
                let ratio = (temperature - a.temperature) / (b.temperature - a.temperature)
                return Int(Double(a.rpm) + ratio * Double(b.rpm - a.rpm))
            }
        }
        return points.last!.rpm
    }

    public func rpm(for temperature: Double, minRPM: Int, maxRPM: Int) -> Int {
        let computed = rpm(for: temperature)
        if computed == 0 { return 0 }
        return max(minRPM, min(maxRPM, computed))
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
        }
        for (i, point) in points.enumerated() {
            if point.temperature < 0 || point.temperature > 120 {
                errors.append("Point \(i): temperature \(point.temperature)°C is out of range (0-120)")
            }
            if !rpmRange.contains(point.rpm) {
                errors.append("Point \(i): RPM \(point.rpm) is out of range (\(rpmRange.lowerBound)-\(rpmRange.upperBound))")
            }
        }
        return errors
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

    public static let auto = Preset(name: "Auto", fanToCurve: [:], fanToSensor: [:])

    public static func quiet(maxRPM: Int) -> Preset {
        quiet(maxRPM: maxRPM, sensorKey: "")
    }

    public static func quiet(maxRPM: Int, sensorKey: String) -> Preset {
        let curve = FanCurve(name: "Quiet", points: [
            CurvePoint(temperature: 30, rpm: 0),
            CurvePoint(temperature: 50, rpm: 1200),
            CurvePoint(temperature: 70, rpm: 2500),
            CurvePoint(temperature: 90, rpm: maxRPM)
        ], sensorKey: sensorKey)
        return Preset(name: "Quiet", fanToCurve: [0: curve], fanToSensor: sensorKey.isEmpty ? [:] : [0: sensorKey])
    }

    public static func balanced(maxRPM: Int) -> Preset {
        balanced(maxRPM: maxRPM, sensorKey: "")
    }

    public static func balanced(maxRPM: Int, sensorKey: String) -> Preset {
        let curve = FanCurve(name: "Balanced", points: [
            CurvePoint(temperature: 30, rpm: 1200),
            CurvePoint(temperature: 50, rpm: 2000),
            CurvePoint(temperature: 70, rpm: 3500),
            CurvePoint(temperature: 85, rpm: maxRPM)
        ], sensorKey: sensorKey)
        return Preset(name: "Balanced", fanToCurve: [0: curve], fanToSensor: sensorKey.isEmpty ? [:] : [0: sensorKey])
    }

    public static func maxCool(maxRPM: Int) -> Preset {
        maxCool(maxRPM: maxRPM, sensorKey: "")
    }

    public static func maxCool(maxRPM: Int, sensorKey: String) -> Preset {
        let curve = FanCurve(name: "MaxCool", points: [
            CurvePoint(temperature: 25, rpm: maxRPM / 2),
            CurvePoint(temperature: 40, rpm: maxRPM)
        ], sensorKey: sensorKey)
        return Preset(name: "MaxCool", fanToCurve: [0: curve], fanToSensor: sensorKey.isEmpty ? [:] : [0: sensorKey])
    }
}
