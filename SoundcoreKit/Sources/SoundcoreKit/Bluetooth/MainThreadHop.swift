import Foundation

/// Runs `body` on the main actor, in call order.
///
/// IOBluetooth delivers most callbacks on the main run loop, but on macOS 27 connection
/// notifications arrive on its private `coordinatorQueue`. Calling main-actor code from there
/// traps, so every IOBluetooth callback goes through here.
nonisolated func onMainActor(_ body: @escaping @MainActor @Sendable () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated { body() }
    } else {
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }
}
