import Foundation
import Combine
import CurveFanCore

@MainActor
public final class PresetViewModel: ObservableObject {
    public static let shared = PresetViewModel(store: .shared)

    @Published public private(set) var presets: [Preset] = []

    private let store: PresetStore

    public init(store: PresetStore) {
        self.store = store
        Task { await refresh() }
    }

    public func refresh() async {
        presets = await store.load()
    }

    public func save(_ preset: Preset) async throws {
        try await store.save(preset)
        presets = await store.load()
    }

    public func delete(id: UUID) async throws {
        try await store.delete(id: id)
        presets = await store.load()
    }
}
