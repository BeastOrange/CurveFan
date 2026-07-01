import SwiftUI
import AppKit
import Combine
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
            curveFanMainWindow = window          // expose for menu bar panel
            NSApplication.shared.setActivationPolicy(.regular)
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    curveFanMainWindow = nil
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
    private var presetCancellable: AnyCancellable?
    /// Active fan curve driven by the poll loop, keyed by fan index. Empty when
    /// no preset curve is running.
    private var activeCurves: [Int: (curve: FanCurve, sensorKey: String)] = [:]
    private var curveEffectiveTemperatures: [Int: Double] = [:]
    private let maxCurveRPMChangePerSecond = 600
    private let maxCurveTemperatureChangePerSecond = 3.0

    init() {
        presetCancellable = PresetManager.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
        Task { await checkDaemon() }
    }

    func checkDaemon() async {
        // First launch: install helper if not present.
        if !HelperInstaller.isInstalled {
            guard HelperInstaller.installIfNeeded() else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000) // let daemon start
        }
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
            curveEffectiveTemperatures[fan] = nil
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
        for fan in 0..<knownFanCount {
            await restoreAuto(fan: fan)
        }
        activePreset = .auto
    }

    func restoreAuto(fan: Int) async {
        activeCurves[fan] = nil
        curveEffectiveTemperatures[fan] = nil
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
        curveEffectiveTemperatures.removeAll()
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
        guard let fallbackCurve = preset.fanToCurve[0] else { return }
        let fallbackSensorKey = preset.fanToSensor[0] ?? fallbackCurve.sensorKey
        guard !fallbackSensorKey.isEmpty else {
            connectionStatus = .error("No readable temperature sensor for preset")
            return
        }

        for fan in 0..<knownFanCount {
            let curve = preset.fanToCurve[fan] ?? fallbackCurve
            let sensorKey = preset.fanToSensor[fan] ?? curve.sensorKey
            guard !sensorKey.isEmpty else {
                connectionStatus = .error("No readable temperature sensor for preset")
                return
            }
            manualFanIDs.remove(fan)
            activeCurves[fan] = (curve: curve, sensorKey: sensorKey)
            curveEffectiveTemperatures[fan] = temperatures.first(where: { $0.key == sensorKey })?.value
        }
        isManualMode = !manualFanIDs.isEmpty
    }

    var maxRPM: Double { fanInfo[0]?.maxRPM ?? 7200 }
    var minRPM: Double { fanInfo[0]?.minRPM ?? 1200 }
    var knownFanCount: Int {
        max(fanInfo.values.map(\.fanCount).max() ?? 1, 1)
    }
    var presets: [Preset] {
        builtInPresets + customPresets
    }

    var builtInPresets: [Preset] {
        PresetManager.shared.defaults(maxRPM: Int(maxRPM), sensorKey: defaultSensorKey)
    }

    var customPresets: [Preset] {
        PresetManager.shared.presets
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
