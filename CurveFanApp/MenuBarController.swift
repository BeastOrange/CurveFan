import SwiftUI
import AppKit
import Combine
import CurveFanCore

/// Bridges SwiftUI's openWindow into AppKit-hosted views (the menu bar panel).
/// Set from the main window's root view; the captured OpenWindowAction stays
/// valid across window lifecycles because it is an app-level action.
@MainActor var curveFanOpenWindow: ((String) -> Void)?

/// Borderless panel that can still become key — required so sliders and
/// buttons inside the SwiftUI content receive events.
final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Self-managed menu bar item + popover panel, replacing MenuBarExtra(.window).
/// The panel sets `sharingType = .readWrite` so window-mode screenshot tools
/// can capture it, which MenuBarExtra(.window) does not allow.
@MainActor
final class StatusItemController: NSObject {
    private let state: AppState
    private var statusItem: NSStatusItem!
    private let panel: StatusPanel
    private var resignObserver: NSObjectProtocol?
    private var cancellable: AnyCancellable?

    init(state: AppState) {
        self.state = state
        self.panel = StatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 372, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        configureStatusItem()
        cancellable = state.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateLabel() }
        }
        updateLabel()
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.sharingType = .readWrite
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:
            MainView(state: state)
                .frame(width: 372)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.target = self
    }

    private func updateLabel() {
        guard let button = statusItem.button else { return }
        let active = state.isCurveFanControlActive
        let image = NSImage(systemSymbolName: active ? "fan.fill" : "fan",
                            accessibilityDescription: "CurveFan")
        image?.isTemplate = true
        button.image = image
        if state.showMenuBarRPM, let rpm = state.fanInfo[0]?.actualRPM {
            button.title = "  \(formatRPM(rpm)) RPM"
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    @objc private func togglePanel() {
        panel.isVisible ? closePanel() : showPanel()
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }

        // Size the panel to the SwiftUI content's natural height.
        panel.contentView?.layoutSubtreeIfNeeded()
        if let size = panel.contentView?.fittingSize, size.width > 0, size.height > 0 {
            panel.setContentSize(size)
        }

        let rectInWindow = button.convert(button.bounds, to: nil)
        let rectOnScreen = buttonWindow.convertToScreen(rectInWindow)
        let panelSize = panel.frame.size
        var origin = NSPoint(x: rectOnScreen.midX - panelSize.width / 2,
                             y: rectOnScreen.minY - panelSize.height - 4)
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let vf = screen.visibleFrame
            origin.x = min(max(vf.minX + 8, origin.x), vf.maxX - panelSize.width - 8)
            if origin.y < vf.minY + 8 { origin.y = vf.minY + 8 }
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)

        // Defer the resign observer so the initial show doesn't self-close.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.panel.isVisible, self.resignObserver == nil else { return }
            self.resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: self.panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.closePanel() }
            }
        }
    }

    private func closePanel() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        panel.orderOut(nil)
    }
}
