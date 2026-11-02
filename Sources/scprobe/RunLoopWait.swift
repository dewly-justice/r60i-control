import Foundation

/// IOBluetooth delivers its callbacks through the main run loop. scprobe is a simple sequential
/// program: everything runs on the main thread, and waiting means running the run loop until a
/// condition holds or a deadline passes.
@MainActor
enum RunLoopWait {
    /// Runs the main run loop until `done()` returns true or `timeout` elapses.
    /// Returns `done()`'s final value.
    @discardableResult
    static func until(timeout: TimeInterval, _ done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !done() {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return done() }
            let result = CFRunLoopRunInMode(.defaultMode, min(remaining, 0.05), true)
            if result == .finished {
                // No sources attached yet; avoid a busy loop.
                Thread.sleep(forTimeInterval: min(remaining, 0.01))
            }
        }
        return true
    }
}
