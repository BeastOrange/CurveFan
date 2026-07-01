import AppKit
import CurveFanCore

/// AppKit-backed WakeEventSource — bridges NSWorkspace.didWakeNotification into the Core protocol.
@MainActor
public struct NSWorkspaceWakeEventSource: WakeEventSource {
    public init() {}

    public func observeWake(using handler: @escaping @Sendable () -> Void) {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            handler()
        }
    }
}
