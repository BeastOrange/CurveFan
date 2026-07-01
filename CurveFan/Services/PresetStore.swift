import Foundation

public actor PresetStore {
    public static let shared = PresetStore()

    private let presetsDir: URL

    public init(presetsDir: URL? = nil) {
        let base = presetsDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CurveFan/presets")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.presetsDir = base
    }

    public func load() async -> [Preset] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: presetsDir, includingPropertiesForKeys: nil)
        } catch {
            NSLog("CurveFan preset listing failed: \(error.localizedDescription)")
            return []
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
        return loaded.sorted { $0.createdAt < $1.createdAt }
    }

    public func save(_ preset: Preset) async throws {
        let data = try JSONEncoder().encode(preset)
        let url = presetsDir.appendingPathComponent("\(preset.id.uuidString).json")
        try data.write(to: url)
    }

    public func delete(id: UUID) async throws {
        let url = presetsDir.appendingPathComponent("\(id.uuidString).json")
        try FileManager.default.removeItem(at: url)
    }
}
