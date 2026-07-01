import SwiftUI
import AppKit

/// Owned by the app root and injected via SwiftUI environment so the menu bar
/// panel (hosted in an NSHostingView without WindowGroup environment access)
/// can open or focus the main window without hidden global state.
@MainActor
final class WindowCoordinator: ObservableObject {
    /// Closure to open a SwiftUI WindowGroup scene by id (set by OpenWindowCapture).
    var openWindow: ((String) -> Void)?
    /// Weak reference to the main NSWindow (set by MainWindowLifecycle).
    weak var mainWindow: NSWindow?

    nonisolated init() {}

    /// Brings the existing main window to front, or opens a new one if closed.
    func openMainWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
        } else {
            openWindow?("main")
        }
    }
}

// MARK: - EnvironmentValues

private struct WindowCoordinatorKey: EnvironmentKey {
    static var defaultValue: WindowCoordinator { WindowCoordinator() }
}

extension EnvironmentValues {
    var windowCoordinator: WindowCoordinator {
        get { self[WindowCoordinatorKey.self] }
        set { self[WindowCoordinatorKey.self] = newValue }
    }
}
