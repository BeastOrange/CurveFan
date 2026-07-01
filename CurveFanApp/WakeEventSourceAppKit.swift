import AppKit
import CurveFanCore

/// AppKit-backed WakeEventSource — bridges NSWorkspace.didWakeNotification into the Core protocol.
///
/// Known limitation: the registered NSWorkspace observer is never removed
/// because WakeEventSource exposes no cancellation surface. The single shared
/// AppState in the running app means this does not leak in practice, but any
/// re-create of AppState (tests, previews, lifecycle changes) would
/// accumulate observers. A follow-up should add a cancellation surface to
/// WakeEventSource (opaque token or AsyncStream).
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
