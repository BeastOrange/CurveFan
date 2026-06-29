import SwiftUI
import AppKit
import CurveFanCore

@main
struct CurveFanApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("CurveFan", id: "main") {
            AppWindowView(state: state)
                .frame(minWidth: 1180, minHeight: 720)
                .background(MainWindowLifecycle())
                // Capture openWindow action and set up status item once.
                .background(OpenWindowCapture())
                .task { appDelegate.setupStatusItem(state: state) }
        }
        .defaultSize(width: 1280, height: 760)

        Settings {
            SettingsView(state: state)
        }
    }
}

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Called from the WindowGroup .task once AppState is ready.
    func setupStatusItem(state: AppState) {
        guard statusItemController == nil else { return }
        statusItemController = StatusItemController(state: state)
    }
}

/// Captures the SwiftUI openWindow action into a global so NSHostingView-hosted
/// views (the menu bar panel) can open the main window without an Environment.
private struct OpenWindowCapture: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear.onAppear {
            curveFanOpenWindow = { id in openWindow(id: id) }
        }
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
    @Published var manualFanIDs: Set<Int> = []
    @Published var manualRPM: Double = 0
    @Published var pollingInterval: TimeInterval = 2.0
    @Published var useFahrenheit = false
    @Published var showMenuBarRPM = true
    @Published var rpmHistory: [RPMHistorySample] = []
    @Published var lastPollDate: Date?

    private let reader = TemperatureReader.shared
    private let controller = FanController.shared
    private let ipc = IPCClient.shared
    private var pollTask: Task<Void, Never>?
    /// Active fan curve driven by the poll loop, keyed by fan index. Empty when
    /// no preset curve is running.
    private var activeCurves: [Int: (curve: FanCurve, sensorKey: String)] = [:]

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
                    let count = max(info.fanCount, 1)
                    if count > 1 {
                        for fan in 1..<count {
                            if let fanInfo = try? await controller.getFanInfo(fan) {
                                self.fanInfo[fan] = fanInfo
                            }
                        }
                    }
                    fanInfo = fanInfo.filter { $0.key < count }
                    lastPollDate = Date()
                    appendRPMHistory(info.actualRPM)
                    if manualRPM == 0 {
                        manualRPM = info.actualRPM
                    }
                    await applyActiveCurves()
                } catch {
                    connectionStatus = .disconnected
                }
            }
        }
    }

    /// Drives any active preset curves from the temperatures and fan info already
    /// fetched this poll cycle, so curve control adds no extra SMC round trips.
    private func applyActiveCurves() async {
        guard !activeCurves.isEmpty else { return }
        for (fan, entry) in activeCurves {
            guard let info = fanInfo[fan],
                  let temp = temperatures.first(where: { $0.key == entry.sensorKey })?.value else {
                continue
            }
            let target = entry.curve.rpm(for: temp, minRPM: Int(info.minRPM), maxRPM: Int(info.maxRPM))
            guard target > 0 else { continue }
            do {
                try await controller.unlockAndSetRPM(fan, rpm: target)
            } catch {
                NSLog("CurveFan curve control failed: \(error.localizedDescription)")
            }
        }
    }

    func setPollingInterval(_ interval: TimeInterval) {
        guard pollingInterval != interval else { return }
        pollingInterval = interval
        if case .connected = connectionStatus {
            startPolling()
        }
    }

    func setManualRPM(_ rpm: Double) async {
        await setManualRPM(rpm, fan: 0)
    }

    func setManualRPM(_ rpm: Double, fan: Int) async {
        do {
            try await controller.unlockAndSetRPM(fan, rpm: Int(rpm))
            activeCurves[fan] = nil
            manualFanIDs.insert(fan)
            isManualMode = true
            if fan == 0 {
                manualRPM = rpm
            }
            if let info = try? await controller.getFanInfo(fan) {
                fanInfo[fan] = info
            }
        } catch {
            connectionStatus = .error(error.localizedDescription)
        }
    }

    func restoreAuto() async {
        await restoreAuto(fan: 0)
    }

    func restoreAuto(fan: Int) async {
        activeCurves[fan] = nil
        manualFanIDs.remove(fan)
        isManualMode = !manualFanIDs.isEmpty
        if fan == 0 {
            activePreset = .auto
        }
        await controller.restoreAutoLogging(fan)
        if let info = try? await controller.getFanInfo(fan) {
            fanInfo[fan] = info
        }
    }

    func restoreAutoForShutdown() async {
        pollTask?.cancel()
        pollTask = nil
        isManualMode = false
        manualFanIDs.removeAll()
        activeCurves.removeAll()
        activePreset = .auto
        for fan in 0..<knownFanCount {
            await controller.restoreAutoLogging(fan)
        }
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
        manualFanIDs.remove(0)
        isManualMode = !manualFanIDs.isEmpty
        activeCurves[0] = (curve: curve, sensorKey: sensorKey)
    }

    var maxRPM: Double { fanInfo[0]?.maxRPM ?? 7200 }
    var minRPM: Double { fanInfo[0]?.minRPM ?? 1200 }
    var knownFanCount: Int {
        max(fanInfo.values.map(\.fanCount).max() ?? 1, 1)
    }
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

    var isCurveFanControlActive: Bool {
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
