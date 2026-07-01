import SwiftUI
import AppKit
import CurveFanCore

struct MainView: View {
    @ObservedObject var state: AppState
    @Environment(\.windowCoordinator) private var windowCoordinator

    var body: some View {
        VStack(spacing: 0) {
            MenuHeaderCard(
                rpm: fanInfo?.actualRPM,
                minRPM: state.minRPM,
                maxRPM: state.maxRPM,
                controlState: controlState
            )

            Divider()

            alertBanner

            // Compact metric row — no card backgrounds
            HStack(spacing: 0) {
                MetricPill(label: "CPU", value: cpuText)
                Divider().frame(height: 28)
                MetricPill(label: "GPU", value: gpuText)
                Divider().frame(height: 28)
                MetricPill(label: "Range", value: rpmRangeText)
            }

            Divider()

            ModeAndPresetSection(
                controlState: controlState,
                presets: curvePresets,
                activePresetName: activePresetName,
                isConnected: isConnected,
                onSystemAuto: { Task { await state.restoreAuto() } },
                onSelectPreset: { preset in Task { await state.applyPreset(preset) } }
            )

            Divider()

            ManualTargetCard(
                manualRPM: $state.manualRPM,
                minRPM: state.minRPM,
                maxRPM: state.maxRPM,
                isConnected: isConnected,
                isActive: state.isManualMode,
                onApply: { Task { await state.setManualRPM(state.manualRPM) } }
            )

            Divider()

            Toggle("Show RPM in menu bar", isOn: $state.showMenuBarRPM)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            FooterToolbar(
                onOpenWindow: {
                    NSApplication.shared.setActivationPolicy(.regular)
                    windowCoordinator.openMainWindow()
                    NSApplication.shared.activate(ignoringOtherApps: true)
                },
                onSettings: showSettings,
                onRestoreAuto: { Task { await state.restoreAuto() } },
                onQuit: { state.quitAfterRestoringAuto() }
            )
        }
        .frame(width: 372)
    }

    // MARK: - Helpers

    private var fanInfo: FanInfo? { state.fanInfo[0] }

    private var isConnected: Bool { state.connectionStatus.isConnected }

    private var activePresetName: String? {
        guard let preset = state.activePreset, !preset.isAuto else { return nil }
        return preset.name
    }

    private var curvePresets: [Preset] { state.presets.filter { !$0.isAuto } }

    private var controlState: MenuControlState {
        guard isConnected else { return .offline }
        if state.isManualMode { return .manual }
        if let activePresetName { return .curve(activePresetName) }
        if fanInfo?.mode == .manual { return .externalManual }
        return .system
    }

    private var cpuText: String { formatSensorText(group: .cpu) }
    private var gpuText: String { formatSensorText(group: .gpu) }
    private var rpmRangeText: String { "\(formatRPM(state.minRPM))–\(formatRPM(state.maxRPM))" }

    @ViewBuilder
    private var alertBanner: some View {
        switch state.connectionStatus {
        case .connected where controlState == .externalManual:
            AlertBanner(icon: "exclamationmark.triangle.fill",
                        text: "Manual fan mode detected. Restore Auto if unintentional.",
                        tint: .orange)
            Divider()
        case .disconnected:
            AlertBanner(icon: "exclamationmark.triangle.fill",
                        text: "Helper disconnected. Run sudo bash setup.sh.",
                        tint: .orange)
            Divider()
        case .error(let msg):
            AlertBanner(icon: "xmark.octagon.fill", text: msg, tint: .red)
            Divider()
        default:
            EmptyView()
        }
    }

    private func formatSensorText(group: SensorGroup) -> String {
        guard let r = state.temperatures.first(where: { $0.group == group }) else { return "--" }
        return state.formatTemp(r.value)
    }

    private func showSettings() {
        state.pendingSectionSelection = .settings
        windowCoordinator.openMainWindow()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

// MARK: - Compact metric pill (no card background)
private struct MetricPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - MenuControlState
enum MenuControlState: Equatable {
    case offline, system, curve(String), manual, externalManual

    var title: String {
        switch self {
        case .offline: return "Helper offline"
        case .system: return "macOS has control"
        case .curve: return "CurveFan curve active"
        case .manual: return "CurveFan manual override"
        case .externalManual: return "Manual mode detected"
        }
    }

    var detail: String {
        switch self {
        case .offline: return "Fan data is unavailable"
        case .system: return "System Auto restores native fan behavior"
        case .curve(let name): return "\(name) curve is writing safe RPM targets"
        case .manual: return "Fixed RPM target is active"
        case .externalManual: return "Current fan mode is manual outside this session"
        }
    }

    var isCurveFanControl: Bool {
        switch self {
        case .curve, .manual: return true
        default: return false
        }
    }

    var tint: Color {
        switch self {
        case .offline: return .red
        case .system: return .green
        case .curve: return .blue
        case .manual: return .orange
        case .externalManual: return .orange
        }
    }
}
