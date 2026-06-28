import SwiftUI
import AppKit
import CurveFanCore

@main
struct CurveFanApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("FanFlow", id: "main") {
            AppWindowView(state: state)
                .frame(minWidth: 1180, minHeight: 720)
                .background(MainWindowLifecycle())
        }
        .defaultSize(width: 1280, height: 760)

        MenuBarExtra {
            MainView(state: state)
                .frame(width: 372, height: 520)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    Task { await state.restoreAutoForShutdown() }
                }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: state.isFanFlowControlActive ? "fan.fill" : "fan")
                if let rpm = state.fanInfo[0]?.actualRPM {
                    Text("\(formatRPM(rpm)) RPM")
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
        }
    }
}

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct MainWindowLifecycle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor in
            guard let window = view.window else { return }
            context.coordinator.observe(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            guard let window = nsView.window else { return }
            context.coordinator.observe(window: window)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var observedWindow: NSWindow?
        private var closeObserver: NSObjectProtocol?

        deinit {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
        }

        @MainActor
        func observe(window: NSWindow) {
            guard observedWindow !== window else { return }
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            observedWindow = window
            NSApplication.shared.setActivationPolicy(.regular)
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
            }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var temperatures: [TemperatureReading] = []
    @Published var fanInfo: [Int: FanInfo] = [:]
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var activePreset: Preset?
    @Published var isManualMode = false
    @Published var manualRPM: Double = 0
    @Published var pollingInterval: TimeInterval = 2.0
    @Published var useFahrenheit = false
    @Published var rpmHistory: [RPMHistorySample] = []

    private let reader = TemperatureReader.shared
    private let controller = FanController.shared
    private let ipc = IPCClient.shared
    private var pollTask: Task<Void, Never>?

    init() {
        Task { await checkDaemon() }
    }

    func checkDaemon() async {
        if await ipc.ping() {
            connectionStatus = .connected
            startPolling()
        } else {
            connectionStatus = .disconnected
        }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            let stream = await reader.stream(interval: pollingInterval)
            for await readings in stream {
                temperatures = readings
                do {
                    let info = try await controller.getFanInfo(0)
                    fanInfo[0] = info
                    appendRPMHistory(info.actualRPM)
                    if manualRPM == 0 {
                        manualRPM = info.actualRPM
                    }
                } catch {
                    connectionStatus = .disconnected
                }
            }
        }
    }

    func setManualRPM(_ rpm: Double) async {
        isManualMode = true
        do {
            try await controller.unlockAndSetRPM(0, rpm: Int(rpm))
        } catch {
            connectionStatus = .error(error.localizedDescription)
        }
    }

    func restoreAuto() async {
        isManualMode = false
        activePreset = .auto
        await controller.stopCurveControl(0)
    }

    func restoreAutoForShutdown() async {
        pollTask?.cancel()
        pollTask = nil
        isManualMode = false
        await controller.stopCurveControl(0)
    }

    func quitAfterRestoringAuto() {
        Task {
            await restoreAutoForShutdown()
            NSApplication.shared.terminate(nil)
        }
    }

    func applyPreset(_ preset: Preset) async {
        activePreset = preset
        if preset.name == "Auto" {
            await restoreAuto()
            return
        }
        guard let curve = preset.fanToCurve[0] else { return }
        let sensorKey = preset.fanToSensor[0] ?? curve.sensorKey
        guard !sensorKey.isEmpty else {
            connectionStatus = .error("No readable temperature sensor for preset")
            return
        }
        isManualMode = false
        await controller.startCurveControl(fan: 0, curve: curve, sensorKey: sensorKey)
    }

    var maxRPM: Double { fanInfo[0]?.maxRPM ?? 7200 }
    var minRPM: Double { fanInfo[0]?.minRPM ?? 1200 }
    var presets: [Preset] {
        PresetManager.shared.defaults(maxRPM: Int(maxRPM), sensorKey: defaultSensorKey)
    }

    var defaultSensorKey: String {
        temperatures.first(where: { $0.group == .cpu })?.key ??
            temperatures.first?.key ??
            ""
    }

    func formatTemp(_ value: Double) -> String {
        let v = useFahrenheit ? value * 9 / 5 + 32 : value
        return String(format: "%.0f°%@", v, useFahrenheit ? "F" : "C")
    }

    func tempColor(_ value: Double) -> Color {
        if value < 50 { return .green }
        if value < 80 { return .orange }
        return .red
    }

    var isFanFlowControlActive: Bool {
        isManualMode || (activePreset?.name != nil && activePreset?.name != "Auto")
    }

    private func appendRPMHistory(_ rpm: Double) {
        rpmHistory.append(RPMHistorySample(date: Date(), rpm: rpm))
        if rpmHistory.count > 48 {
            rpmHistory.removeFirst(rpmHistory.count - 48)
        }
    }
}

struct RPMHistorySample: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let rpm: Double
}
