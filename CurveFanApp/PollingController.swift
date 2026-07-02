import Foundation
import CurveFanCore

/// Owns the polling Task lifecycle. Calls back into the provided onTick closure
/// for each batch of temperature readings, leaving per-tick state updates to the caller.
@MainActor
final class PollingController {
    private var pollTask: Task<Void, Never>?
    private let reader = TemperatureReader.shared

    func start(interval: TimeInterval, onTick: @escaping ([TemperatureReading]) async -> Void) {
        pollTask?.cancel()
        pollTask = Task {
            let stream = await reader.stream(interval: interval)
            for await readings in stream {
                await onTick(readings)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }
}
