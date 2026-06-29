import SwiftUI
import AppKit
import CurveFanCore

struct MainView: View {
    @ObservedObject var state: AppState
    // openWindow is unavailable in NSHostingView; use the global bridge set by OpenWindowCapture

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
                    curveFanOpenWindow?("main")
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

    private var isConnected: Bool {
        if case .connected = state.connectionStatus { return true }
        return false
    }

    private var activePresetName: String? {
        guard let name = state.activePreset?.name, name != "Auto" else { return nil }
        return name
    }

    private var curvePresets: [Preset] { state.presets.filter { $0.name != "Auto" } }

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
        NSApplication.shared.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApplication.shared.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
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

// MARK: - MenuControlState & SettingsView (unchanged)
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

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        TabView {
            Form {
                Toggle("Fahrenheit", isOn: $state.useFahrenheit)
                Picker("Polling interval", selection: $state.pollingInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
            }
            .tabItem { Text("General") }
            .padding()

            Form {
                Section("About") {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    LabeledContent("Version", value: "CurveFan \(version)")
                    LabeledContent("License", value: "MIT")
                }
            }
            .tabItem { Text("About") }
            .padding()
        }
        .frame(width: 360, height: 200)
    }
}
