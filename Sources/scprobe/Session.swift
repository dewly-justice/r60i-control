import Foundation
import SoundcoreProtocol

/// Request/response over the RFCOMM link: docs/protocol.md §3.
/// - The reply is the next inbound frame with the same command.
/// - Resend after 0.5 s, then 1 s, then 1.5 s, then give up.
/// - Any other inbound frame is a push and goes to `onPush`.
@MainActor
final class Session {
    static let retryTimeouts: [TimeInterval] = [0.5, 1.0, 1.5]

    private let link: RFCOMMLink
    private let log: Log
    private var decoder = FrameDecoder(expecting: .deviceToHost)
    private var awaiting: Command?
    private var reply: Frame?

    var onPush: ((Frame) -> Void)?

    init(link: RFCOMMLink, log: Log) {
        self.link = link
        self.log = log
        link.onData = { [unowned self] bytes in receive(bytes) }
    }

    private func receive(_ bytes: [UInt8]) {
        for event in decoder.feed(bytes) {
            switch event {
            case let .frame(frame):
                log.frame(frame)
                if let awaiting, reply == nil, frame.command == awaiting {
                    reply = frame
                } else {
                    onPush?(frame)
                }
            case let .discarded(dropped, reason):
                log.info("warning: dropped \(dropped.count) inbound bytes (\(reason)): \(dropped.hexString)")
            }
        }
    }

    /// Sends `frame` and returns the matching reply (for writes, the ACK).
    func send(_ frame: Frame) throws -> Frame {
        awaiting = frame.command
        reply = nil
        defer { awaiting = nil }

        let bytes = frame.encoded()
        for (attempt, timeout) in Self.retryTimeouts.enumerated() {
            var note = frame.command.name.map { "\(frame.command) \($0)" } ?? "\(frame.command)"
            if attempt > 0 { note += ", retry \(attempt)" }
            try link.write(bytes, note: note)

            RunLoopWait.until(timeout: timeout) { reply != nil || !link.isOpen }
            if let reply { return reply }
            if !link.isOpen { throw ProbeError.channelClosed }
        }
        throw ProbeError.timeout(frame.command)
    }

    func readState() throws -> D1202State {
        let reply = try send(Requests.requestState())
        do {
            return try D1202State(body: reply.body)
        } catch {
            throw ProbeError.parse(error)
        }
    }

    /// Keeps the channel open so pushes print, until `seconds` pass, the channel closes, or `stop()` is true.
    func listen(seconds: TimeInterval, stop: () -> Bool) {
        RunLoopWait.until(timeout: seconds) { stop() || !link.isOpen }
    }
}
