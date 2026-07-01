// SignalHandling.swift -- DispatchSourceSignal wrapper for SIGTERM/SIGINT.
// The dispatch source handler runs on a serial queue, never inside the signal
// context, so the registered cleanup closure may perform I/O and IOKit calls.

import Foundation
import Darwin

actor SignalHandling {
    private let queue: DispatchQueue
    private var cleanup: (() -> Void)?
    private var installed = false
    private var sources: [DispatchSourceSignal] = []

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func install(using perform: @Sendable @escaping () -> Void) async {
        precondition(!installed, "SignalHandling.install must only be called once")
        installed = true
        cleanup = perform
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            source.setEventHandler { [weak self] in
                Task { await self?.fire() }
            }
            source.resume()
            sources.append(source)
        }
    }

    private func fire() async {
        let work = cleanup
        cleanup = nil
        work?()
    }
}
