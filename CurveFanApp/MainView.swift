import SwiftUI
import AppKit
import CurveFanCore

struct MainView: View {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            MenuHeaderCard(
                rpm: fanInfo?.actualRPM,
                minRPM: state.minRPM,
                maxRPM: state.maxRPM,
                cpuText: cpuText,
                gpuText: gpuText,
                controlState: controlState
            )

            connectionBanner

            QuickMetricGrid(
                rpm: fanInfo?.actualRPM,
                rangeText: rpmRangeText,
                cpuText: cpuText,
                gpuText: gpuText,
                pollingText: "\(Int(state.pollingInterval))s"
            )

            ControlModeChooser(
                controlState: controlState,
                curveName: preferredCurvePreset?.name ?? "Balanced",
                onSystemAuto: {
                    Task { await state.restoreAuto() }
                },
                onFanFlow: {
                    guard let preset = preferredCurvePreset else { return }
                    Task { await state.applyPreset(preset) }
                }
            )

            PresetStrip(
                presets: curvePresets,
                activePresetName: activePresetName,
                isEnabled: isConnected,
                onSelect: { preset in
                    Task { await state.applyPreset(preset) }
                }
            )

            ManualTargetCard(
                manualRPM: $state.manualRPM,
                minRPM: state.minRPM,
                maxRPM: state.maxRPM,
                isConnected: isConnected,
                isActive: state.isManualMode,
                onApply: {
                    Task { await state.setManualRPM(state.manualRPM) }
                }
            )

            FooterToolbar(
                onOpenWindow: {
                    NSApplication.shared.setActivationPolicy(.regular)
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                },
                onSettings: showSettings,
                onRestoreAuto: {
                    Task { await state.restoreAuto() }
                },
                onQuit: {
                    state.quitAfterRestoringAuto()
                }
            )
        }
        .padding(12)
        .frame(width: 372)
        .background(menuBackground)
    }

    private var fanInfo: FanInfo? {
        state.fanInfo[0]
    }

    private var isConnected: Bool {
        if case .connected = state.connectionStatus { return true }
        return false
    }

    private var activePresetName: String? {
        guard let name = state.activePreset?.name, name != "Auto" else { return nil }
        return name
    }

    private var curvePresets: [Preset] {
        state.presets.filter { $0.name != "Auto" }
    }

    private var preferredCurvePreset: Preset? {
        if let activePresetName,
           let current = curvePresets.first(where: { $0.name == activePresetName }) {
            return current
        }
        return curvePresets.first(where: { $0.name == "Balanced" }) ?? curvePresets.first
    }

    private var controlState: MenuControlState {
        guard isConnected else { return .offline }
        if state.isManualMode { return .manual }
        if let activePresetName { return .curve(activePresetName) }
        if fanInfo?.mode == .manual { return .externalManual }
        return .system
    }

    private var cpuText: String {
        formatSensorText(group: .cpu)
    }

    private var gpuText: String {
        formatSensorText(group: .gpu)
    }

    private var rpmRangeText: String {
        "\(formatRPM(state.minRPM))-\(formatRPM(state.maxRPM))"
    }

    @ViewBuilder
    private var connectionBanner: some View {
        switch state.connectionStatus {
        case .connected:
            if controlState == .externalManual {
                AlertBanner(
                    icon: "exclamationmark.triangle.fill",
                    text: "Manual fan mode detected. Restore Auto if this was not intentional.",
                    tint: .orange
                )
            }
        case .disconnected:
            AlertBanner(
                icon: "exclamationmark.triangle.fill",
                text: "Helper disconnected. Run sudo bash setup.sh.",
                tint: .orange
            )
        case .error(let message):
            AlertBanner(icon: "xmark.octagon.fill", text: message, tint: .red)
        }
    }

    private var menuBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.03),
                    Color.accentColor.opacity(0.08),
                    Color.black.opacity(0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func formatSensorText(group: SensorGroup) -> String {
        guard let reading = state.temperatures.first(where: { $0.group == group }) else {
            return "--"
        }
        return state.formatTemp(reading.value)
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

enum MenuControlState: Equatable {
    case offline
    case system
    case curve(String)
    case manual
    case externalManual

    var title: String {
        switch self {
        case .offline: return "Helper offline"
        case .system: return "macOS has control"
        case .curve: return "FanFlow curve active"
        case .manual: return "FanFlow manual override"
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

    var isFanFlowControl: Bool {
        switch self {
        case .curve, .manual: return true
        case .offline, .system, .externalManual: return false
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
                Toggle("华氏度", isOn: $state.useFahrenheit)
                Picker("更新间隔", selection: $state.pollingInterval) {
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("5 秒").tag(5.0)
                }
            }
            .tabItem { Text("通用") }
            .padding()

            Form {
                Section("关于") {
                    Text("CurveFan v1.0.0")
                    Text("开源风扇控制软件")
                    Text("MIT License")
                }
            }
            .tabItem { Text("关于") }
            .padding()
        }
        .frame(width: 400, height: 300)
    }
}
