import SwiftUI
import CurveFanCore

struct OverviewView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                PageHeader(
                    subtitle: "Apple Silicon thermal and fan control",
                    isConnected: isConnected,
                    onRetry: { Task { await state.reconnect() } }
                )

                OverviewSummaryGroup(
                    rpm: fanInfo?.actualRPM,
                    minRPM: state.minRPM,
                    maxRPM: state.maxRPM,
                    pollingInterval: state.pollingInterval,
                    controlText: controlSummary,
                    cpuText: sensorText(.cpu),
                    gpuText: sensorText(.gpu),
                    pollingText: "\(Int(state.pollingInterval))s",
                    samples: state.rpmHistory
                )

                HStack(alignment: .top, spacing: DesignTokens.Spacing.section) {
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
                        .frame(minWidth: 260, maxWidth: 340)
                }
            }
            .padding(DesignTokens.Spacing.page)
        }
    }

    private var fanInfo: FanInfo? {
        state.fanInfo[0]
    }

    private var isConnected: Bool { state.connectionStatus.isConnected }
    private var selectedPreset: Preset? {
        if let activeName = state.activePreset?.name,
           !(state.activePreset?.isAuto ?? false),
           let current = state.presets.first(where: { $0.name == activeName }) {
            return current
        }
        return state.presets.first(where: { $0.name == "Balanced" })
    }

    private var controlSummary: String {
        let fanLabel = fanInfo.map { "\($0.fanCount) fan\($0.fanCount == 1 ? "" : "s")" } ?? "fan data pending"
        if state.isManualMode { return "Manual override - \(fanLabel)" }
        if let name = state.activePreset?.name, !(state.activePreset?.isAuto ?? false) {
            return "Curve - \(name) - \(fanLabel)"
        }
        return "System Auto - \(fanLabel)"
    }

    private func sensorText(_ group: SensorGroup) -> String {
        guard let reading = state.temperatures.first(where: { $0.group == group }) else {
            return "--"
        }
        return TempFormatter().format(reading.value, useFahrenheit: state.useFahrenheit)
    }
}

struct OverviewSummaryGroup: View {
    let rpm: Double?
    let minRPM: Double
    let maxRPM: Double
    let pollingInterval: TimeInterval
    let controlText: String
    let cpuText: String
    let gpuText: String
    let pollingText: String
    let samples: [RPMHistorySample]

    var body: some View {
        CardView(title: "Overview", systemImage: "gauge.with.dots.needle.50percent") {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.compact) {
                        Text(rpm.map { "\(formatRPM($0)) RPM" } ?? "-- RPM")
                            .font(DesignTokens.Typography.largeRPM)
                            .monospacedDigit()
                        Text(controlText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: DesignTokens.Spacing.section) {
                    RPMTrendChart(
                        samples: samples,
                        currentRPM: rpm,
                        minRPM: minRPM,
                        maxRPM: maxRPM,
                        pollingInterval: pollingInterval
                    )
                    .frame(height: 168)

                    NativeMetricTable(
                        rows: [
                            ("CPU", cpuText),
                            ("GPU", gpuText),
                            ("Poll", pollingText)
                        ]
                    )
                    .frame(maxWidth: 200)
                }
            }
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
        CardView(title: "Fan Controls", systemImage: "fan") {
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
                        ForEach(state.presets.filter { !$0.isAuto }) { preset in
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
        }
    }

    private var controlBinding: Binding<OverviewControlMode> {
        Binding(
            get: {
                if state.isManualMode { return .manual }
                if !(state.activePreset?.isAuto ?? false) { return .curve }
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
