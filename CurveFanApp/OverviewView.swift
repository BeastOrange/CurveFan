import SwiftUI
import CurveFanCore

struct OverviewView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    subtitle: "Apple Silicon thermal and fan control",
                    isConnected: isConnected
                )

                OverviewSummaryGroup(
                    rpm: fanInfo?.actualRPM,
                    minRPM: state.minRPM,
                    maxRPM: state.maxRPM,
                    controlText: controlSummary,
                    cpuText: sensorText(.cpu),
                    gpuText: sensorText(.gpu),
                    pollingText: "\(Int(state.pollingInterval))s",
                    samples: state.rpmHistory
                )

                HStack(alignment: .top, spacing: 18) {
                    FanControlsGroup(
                        state: state,
                        selectedPreset: selectedPreset,
                        onRestoreAuto: {
                            Task { await state.restoreAuto() }
                        },
                        onApplyPreset: {
                            guard let preset = selectedPreset else { return }
                            Task { await state.applyPreset(preset) }
                        },
                        onApplyManual: {
                            Task { await state.setManualRPM(state.manualRPM) }
                        }
                    )
                    .frame(maxWidth: .infinity)

                    PreferencesGroup(state: state)
                        .frame(width: 340)
                }
            }
            .padding(24)
            .frame(maxWidth: 1180, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var fanInfo: FanInfo? {
        state.fanInfo[0]
    }

    private var isConnected: Bool {
        if case .connected = state.connectionStatus { return true }
        return false
    }
    private var selectedPreset: Preset? {
        if let activeName = state.activePreset?.name,
           activeName != "Auto",
           let current = state.presets.first(where: { $0.name == activeName }) {
            return current
        }
        return state.presets.first(where: { $0.name == "Balanced" })
    }

    private var controlSummary: String {
        let fanLabel = fanInfo.map { "\($0.fanCount) fan\($0.fanCount == 1 ? "" : "s")" } ?? "fan data pending"
        if state.isManualMode { return "Manual override - \(fanLabel)" }
        if let name = state.activePreset?.name, name != "Auto" {
            return "Curve - \(name) - \(fanLabel)"
        }
        return "System Auto - \(fanLabel)"
    }

    private func sensorText(_ group: SensorGroup) -> String {
        guard let reading = state.temperatures.first(where: { $0.group == group }) else {
            return "--"
        }
        return state.formatTemp(reading.value)
    }
}

struct OverviewSummaryGroup: View {
    let rpm: Double?
    let minRPM: Double
    let maxRPM: Double
    let controlText: String
    let cpuText: String
    let gpuText: String
    let pollingText: String
    let samples: [RPMHistorySample]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(rpm.map { "\(formatRPM($0)) RPM" } ?? "-- RPM")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(controlText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 18) {
                    RPMTrendChart(
                        samples: samples,
                        currentRPM: rpm,
                        minRPM: minRPM,
                        maxRPM: maxRPM
                    )
                    .frame(height: 168)

                    NativeMetricTable(
                        rows: [
                            ("CPU", cpuText),
                            ("GPU", gpuText),
                            ("Poll", pollingText)
                        ]
                    )
                    .frame(width: 220)
                }
            }
            .padding(6)
        } label: {
            Label("Overview", systemImage: "gauge.with.dots.needle.50percent")
        }
    }
}

struct FanControlsGroup: View {
    @ObservedObject var state: AppState
    let selectedPreset: Preset?
    let onRestoreAuto: () -> Void
    let onApplyPreset: () -> Void
    let onApplyManual: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Control mode") {
                    Picker("Control mode", selection: controlBinding) {
                        Text("System").tag(OverviewControlMode.system)
                        Text("Curve").tag(OverviewControlMode.curve)
                        Text("Manual").tag(OverviewControlMode.manual)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Manual target")
                        .font(.headline)
                    Text(state.isManualMode ? "Fixed RPM target is active." : "Inactive unless Manual is applied.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Slider(value: $state.manualRPM, in: state.minRPM...state.maxRPM, step: 100)

                    HStack {
                        Text("Min \(formatRPM(state.minRPM)) RPM")
                        Spacer()
                        Text("Max \(formatRPM(state.maxRPM)) RPM")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Presets")
                        .font(.headline)
                    HStack(spacing: 8) {
                        ForEach(state.presets.filter { $0.name != "Auto" }) { preset in
                            PresetButton(
                                preset: preset,
                                isSelected: selectedPreset?.name == preset.name,
                                maxRPM: state.maxRPM,
                                action: { Task { await state.applyPreset(preset) } }
                            )
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Revert", action: onRestoreAuto)
                    Button("Apply \(selectedPreset?.name ?? "Curve")", action: onApplyPreset)
                        .buttonStyle(.borderedProminent)
                    Button("Apply Manual", action: onApplyManual)
                }
            }
            .padding(6)
        } label: {
            Label("Fan Controls", systemImage: "fan")
        }
    }

    private var controlBinding: Binding<OverviewControlMode> {
        Binding(
            get: {
                if state.isManualMode { return .manual }
                if let name = state.activePreset?.name, name != "Auto" { return .curve }
                return .system
            },
            set: { mode in
                switch mode {
                case .system:
                    onRestoreAuto()
                case .curve:
                    onApplyPreset()
                case .manual:
                    break
                }
            }
        )
    }
}

enum OverviewControlMode: Hashable {
    case system
    case curve
    case manual
}
