import Foundation
import CurveFanCore

/// Owns active fan curves, effective-temperature tracking, and the rate-limited
/// curve-evaluation + SMC-write engine that drives preset-based fan control.
@MainActor
final class CurveApplicator {
    private var activeCurves: [Int: (curve: FanCurve, sensorKey: String)] = [:]
    private var curveEffectiveTemperatures: [Int: Double] = [:]
    private let maxCurveRPMChangePerSecond = 600
    private let maxCurveTemperatureChangePerSecond = 3.0
    private let controller = FanController.shared

    func setCurve(fan: Int, curve: FanCurve, sensorKey: String, initialTemperature: Double?) {
        activeCurves[fan] = (curve: curve, sensorKey: sensorKey)
        curveEffectiveTemperatures[fan] = initialTemperature
    }

    func clearCurve(fan: Int) {
        activeCurves[fan] = nil
        curveEffectiveTemperatures[fan] = nil
    }

    func clearAll() {
        activeCurves.removeAll()
        curveEffectiveTemperatures.removeAll()
    }

    var hasActiveCurves: Bool { !activeCurves.isEmpty }

    /// Drives any active preset curves from the temperatures and fan info already
    /// fetched this poll cycle, so curve control adds no extra SMC round trips.
    func applyActiveCurves(temperatures: [TemperatureReading], fanInfo: [Int: FanInfo], pollingInterval: TimeInterval) async {
        guard !activeCurves.isEmpty else { return }
        for (fan, entry) in activeCurves {
            guard let info = fanInfo[fan],
                  let temp = temperatures.first(where: { $0.key == entry.sensorKey })?.value else {
                continue
            }
            let effectiveTemperature = FanCurve.rateLimitedTemperature(
                current: curveEffectiveTemperatures[fan] ?? temp,
                target: temp,
                interval: pollingInterval,
                maxChangePerSecond: maxCurveTemperatureChangePerSecond
            )
            curveEffectiveTemperatures[fan] = effectiveTemperature

            let target = entry.curve.rpm(
                for: effectiveTemperature,
                minRPM: Int(info.minRPM),
                maxRPM: Int(info.maxRPM)
            )
            guard target > 0 else {
                curveEffectiveTemperatures[fan] = nil
                await controller.restoreAutoLogging(fan)
                continue
            }
            let current = Int(info.actualRPM)
            let limitedTarget = FanCurve.rateLimitedRPM(
                current: current,
                target: target,
                interval: pollingInterval,
                maxRPMChangePerSecond: maxCurveRPMChangePerSecond
            )
            do {
                try await controller.unlockAndSetRPM(fan, rpm: limitedTarget)
            } catch {
                NSLog("CurveFan curve control failed: \(error.localizedDescription)")
            }
        }
    }
}
