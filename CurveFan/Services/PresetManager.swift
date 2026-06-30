import Foundation

public final class PresetManager: ObservableObject, @unchecked Sendable {
    public static let shared = PresetManager()

    @Published public var presets: [Preset] = []

    private let presetsDir: URL

    public init(presetsDir: URL? = nil) {
        let base = presetsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CurveFan/presets")
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            NSLog("CurveFan preset directory creation failed: \(error.localizedDescription)")
        }
        self.presetsDir = base
        loadAll()
    }

    public func save(_ preset: Preset) throws {
        let data = try JSONEncoder().encode(preset)
        let url = presetsDir.appendingPathComponent("\(preset.id.uuidString).json")
        try data.write(to: url)
        if let idx = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[idx] = preset
        } else {
            presets.append(preset)
        }
    }

    public func delete(id: UUID) throws {
        let url = presetsDir.appendingPathComponent("\(id.uuidString).json")
        try FileManager.default.removeItem(at: url)
        presets.removeAll { $0.id == id }
    }

    public func loadAll() {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: presetsDir, includingPropertiesForKeys: nil)
        } catch {
            NSLog("CurveFan preset listing failed: \(error.localizedDescription)")
            presets = []
            return
        }
        let loaded = files.compactMap { url -> Preset? in
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(Preset.self, from: data)
            } catch {
                NSLog("CurveFan preset load failed for \(url.lastPathComponent): \(error.localizedDescription)")
                return nil
            }
        }
        presets = loaded.sorted { $0.createdAt < $1.createdAt }
    }

    public var defaults: [Preset] {
        defaults(maxRPM: 7200)
    }

    public func defaults(maxRPM: Int) -> [Preset] {
        defaults(maxRPM: maxRPM, sensorKey: "")
    }

    public func defaults(maxRPM: Int, sensorKey: String) -> [Preset] {
        return [
            .auto,
            .quiet(maxRPM: maxRPM, sensorKey: sensorKey),
            .balanced(maxRPM: maxRPM, sensorKey: sensorKey),
            .maxCool(maxRPM: maxRPM, sensorKey: sensorKey)
        ]
    }
}
