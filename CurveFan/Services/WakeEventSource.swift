import Foundation

/// Observer hook for system wake events, abstracted so Core doesn't import AppKit.
public protocol WakeEventSource: Sendable {
    /// Registers a closure to be invoked when the system wakes from sleep.
    func observeWake(using handler: @escaping @Sendable () -> Void) async
}
