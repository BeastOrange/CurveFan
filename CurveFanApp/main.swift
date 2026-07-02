import SwiftUI
import AppKit
import Combine
import CurveFanCore

@main
struct CurveFanApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var windowCoordinator = WindowCoordinator()

    var body: some Scene {
        WindowGroup("CurveFan", id: "main") {
            AppWindowView(state: state)
                .frame(minWidth: 1180, minHeight: 720)
                .background(MainWindowLifecycle(coordinator: windowCoordinator))
                .background(OpenWindowCapture())
                .environment(\.windowCoordinator, windowCoordinator)
                .task { appDelegate.setupStatusItem(state: state, coordinator: windowCoordinator) }
        }
        .defaultSize(width: 1280, height: 760)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    state.pendingSectionSelection = .settings
                    windowCoordinator.openMainWindow()
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
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
    func setupStatusItem(state: AppState, coordinator: WindowCoordinator) {
        guard statusItemController == nil else { return }
        statusItemController = StatusItemController(state: state, coordinator: coordinator)
    }
}

/// Captures the SwiftUI openWindow action into the WindowCoordinator so
/// NSHostingView-hosted views (the menu bar panel) can open the main window.
private struct OpenWindowCapture: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.windowCoordinator) private var coordinator
    var body: some View {
        Color.clear.onAppear {
            coordinator.openWindow = { id in openWindow(id: id) }
        }
    }
}

struct MainWindowLifecycle: NSViewRepresentable {
    let coordinator: WindowCoordinator

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.windowCoordinator = coordinator
        Task { @MainActor in
            guard let window = view.window else { return }
            context.coordinator.observe(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.windowCoordinator = coordinator
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
        var windowCoordinator: WindowCoordinator?

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
            windowCoordinator?.mainWindow = window
            NSApplication.shared.setActivationPolicy(.regular)
            let wc = windowCoordinator
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    wc?.mainWindow = nil
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
    /// Set by menu bar panel / external callers to request a sidebar navigation in the main window; observed by AppWindowView and cleared after consumption.
    @Published var pendingSectionSelection: AppSection? = nil

    private let controller = FanController.shared
    private let ipc = IPCClient.shared
    private let pollingController = PollingController()
    private let curveApplicator = CurveApplicator()
    private lazy var presetActions = PresetActions(state: self, curveApplicator: curveApplicator)
    private var presetCancellable: AnyCancellable?

    init() {
        presetCancellable = PresetViewModel.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
        Task { await checkDaemon() }
        Task { await controller.observeWakeEvents(from: NSWorkspaceWakeEventSource()) }
    }

    func checkDaemon() async {
        if !HelperInstaller.isInstalled {
            guard HelperInstaller.installIfNeeded() else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }

        for attempt in 1...5 {
            if await ipc.ping() {
                connectionStatus = .connected
                startPolling()
                return
            }
            if attempt < 5 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        if HelperInstaller.isInstalled, await ipc.legacyPing() {
            guard HelperInstaller.installIfNeeded(force: true) else {
                connectionStatus = .error("Installed helper is outdated. Please update it.")
                return
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if await ipc.ping() {
                connectionStatus = .connected
                startPolling()
                return
            }
        }

        connectionStatus = .disconnected
    }

    /// Force a fresh connection check. Useful after manual helper repair or when UI shows Offline.
    func reconnect() async {
        pollingController.stop()
        connectionStatus = .disconnected
        await checkDaemon()
    }

    func startPolling() {
        pollingController.start(interval: pollingInterval) { [weak self] readings in
            await self?.handlePollTick(readings)
        }
    }

    private func handlePollTick(_ readings: [TemperatureReading]) async {
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
            await curveApplicator.applyActiveCurves(
                temperatures: temperatures,
                fanInfo: fanInfo,
                pollingInterval: pollingInterval)
        } catch {
            connectionStatus = .disconnected
        }
    }

    func setPollingInterval(_ interval: TimeInterval) {
        guard pollingInterval != interval else { return }
        pollingInterval = interval
        if case .connected = connectionStatus {
            startPolling()
        }
    }

    func setManualRPM(_ rpm: Double) async { await setManualRPM(rpm, fan: 0) }
    func setManualRPM(_ rpm: Double, fan: Int) async { await presetActions.setManualRPM(rpm, fan: fan) }

    func restoreAuto() async {
        await presetActions.restoreAuto(knownFanCount: knownFanCount)
        activePreset = .auto
    }
    func restoreAuto(fan: Int) async {
        await presetActions.restoreAuto(fan: fan)
        if fan == 0 { activePreset = .auto }
    }

    func restoreAutoForShutdown() async {
        pollingController.stop()
        await presetActions.restoreAutoForShutdown(knownFanCount: knownFanCount)
    }

    func quitAfterRestoringAuto() {
        Task {
            await restoreAutoForShutdown()
            NSApplication.shared.terminate(nil)
        }
    }

    func applyPreset(_ preset: Preset) async {
        activePreset = preset
        if preset.isAuto {
            await restoreAuto()
            return
        }
        await presetActions.applyPreset(preset, knownFanCount: knownFanCount, temperatures: temperatures)
    }

    var maxRPM: Double { fanInfo[0]?.maxRPM ?? 7200 }
    var minRPM: Double { fanInfo[0]?.minRPM ?? 1200 }
    var knownFanCount: Int { max(fanInfo.values.map(\.fanCount).max() ?? 1, 1) }
    var presets: [Preset] { builtInPresets + customPresets }
    var builtInPresets: [Preset] { PresetFactory.defaults(maxRPM: Int(maxRPM), sensorKey: defaultSensorKey) }
    var customPresets: [Preset] { PresetViewModel.shared.presets }
    var defaultSensorKey: String {
        temperatures.first(where: { $0.group == .cpu })?.key ?? temperatures.first?.key ?? ""
    }
    var isCurveFanControlActive: Bool {
        isManualMode || (activePreset?.isAuto == false)
    }

    private func appendRPMHistory(_ rpm: Double) {
        rpmHistory.append(RPMHistorySample(date: Date(), rpm: rpm))
        if rpmHistory.count > RPMHistoryChartConfig.retainedSamples {
            rpmHistory.removeFirst(rpmHistory.count - RPMHistoryChartConfig.retainedSamples)
        }
    }
}

enum RPMHistoryChartConfig {
    static let visibleIntervals = 48
    // Keep one extra sample so the chart can interpolate the sliding window's left edge.
    static let retainedSamples = visibleIntervals + 1
}

struct RPMHistorySample: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let rpm: Double
}
