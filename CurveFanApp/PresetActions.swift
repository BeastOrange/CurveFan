import Foundation
import CurveFanCore

/// Owns preset application, manual-RPM entry, and manual-mode exit logic.
/// Mutates AppState @Published properties through a weak reference and
/// manages curve state through CurveApplicator.
@MainActor
final class PresetActions {
    private weak var state: AppState?
    private let curveApplicator: CurveApplicator
    private let controller = FanController.shared

    init(state: AppState, curveApplicator: CurveApplicator) {
        self.state = state
        self.curveApplicator = curveApplicator
    }

    func setManualRPM(_ rpm: Double, fan: Int) async {
        do {
            try await controller.unlockAndSetRPM(fan, rpm: Int(rpm))
            curveApplicator.clearCurve(fan: fan)
            state?.manualFanIDs.insert(fan)
            state?.isManualMode = true
            if fan == 0 {
                state?.manualRPM = rpm
            }
            if let info = try? await controller.getFanInfo(fan) {
                state?.fanInfo[fan] = info
            }
        } catch {
            state?.connectionStatus = .error(error.localizedDescription)
        }
    }

    func restoreAuto(fan: Int) async {
        curveApplicator.clearCurve(fan: fan)
        state?.manualFanIDs.remove(fan)
        state?.isManualMode = !(state?.manualFanIDs.isEmpty ?? true)
        await controller.restoreAutoLogging(fan)
        if let info = try? await controller.getFanInfo(fan) {
            state?.fanInfo[fan] = info
        }
    }

    func restoreAuto(knownFanCount: Int) async {
        for fan in 0..<knownFanCount {
            await restoreAuto(fan: fan)
        }
    }

    func restoreAutoForShutdown(knownFanCount: Int) async {
        state?.isManualMode = false
        state?.manualFanIDs.removeAll()
        curveApplicator.clearAll()
        state?.activePreset = .auto
        for fan in 0..<knownFanCount {
            await controller.restoreAutoLogging(fan)
        }
    }

    func applyPreset(_ preset: Preset, knownFanCount: Int, temperatures: [TemperatureReading]) async {
        guard let fallbackCurve = preset.fanToCurve[0] else { return }
        let fallbackSensorKey = preset.fanToSensor[0] ?? fallbackCurve.sensorKey
        guard !fallbackSensorKey.isEmpty else {
            state?.connectionStatus = .error("No readable temperature sensor for preset")
            return
        }
        for fan in 0..<knownFanCount {
            let curve = preset.fanToCurve[fan] ?? fallbackCurve
            let sensorKey = preset.fanToSensor[fan] ?? curve.sensorKey
            guard !sensorKey.isEmpty else {
                state?.connectionStatus = .error("No readable temperature sensor for preset")
                return
            }
            state?.manualFanIDs.remove(fan)
            let initialTemp = temperatures.first(where: { $0.key == sensorKey })?.value
            curveApplicator.setCurve(fan: fan, curve: curve, sensorKey: sensorKey, initialTemperature: initialTemp)
        }
        state?.isManualMode = !(state?.manualFanIDs.isEmpty ?? true)
    }
}
