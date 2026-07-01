import Foundation

public enum PresetFactory {
    public static var defaults: [Preset] {
        defaults(maxRPM: 7200)
    }

    public static func defaults(maxRPM: Int) -> [Preset] {
        defaults(maxRPM: maxRPM, sensorKey: "")
    }

    public static func defaults(maxRPM: Int, sensorKey: String) -> [Preset] {
        return [
            .auto,
            .quiet(maxRPM: maxRPM, sensorKey: sensorKey),
            .balanced(maxRPM: maxRPM, sensorKey: sensorKey),
            .maxCool(maxRPM: maxRPM, sensorKey: sensorKey)
        ]
    }
}
