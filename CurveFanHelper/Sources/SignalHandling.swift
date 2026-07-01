// SignalHandling.swift -- DispatchSourceSignal wrapper for SIGTERM/SIGINT.
// The dispatch source handler runs on a serial queue, never inside the signal
// context, so the registered cleanup closure may perform I/O and IOKit calls.

import Foundation
import Darwin

final class SignalHandling: @unchecked Sendable {
    private let queue: DispatchQueue
    private var cleanup: (() -> Void)?
    private var installed = false
    private var sources: [DispatchSourceSignal] = []

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// Registers a cleanup closure to run when SIGTERM or SIGINT is delivered.
    /// The closure runs on the queue passed to init; it is never invoked inside
    /// the raw signal handler. Calling install more than once is a programmer error.
    func install(using perform: @escaping () -> Void) {
        precondition(!installed, "SignalHandling.install must only be called once")
        installed = true
        cleanup = perform
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            source.setEventHandler { [weak self] in
                self?.fire()
            }
            source.resume()
            sources.append(source)
        }
    }

    private func fire() {
        let work = cleanup
        cleanup = nil
        work?()
        exit(0)
    }
}
