import Foundation

/// What went over the link, for `--hexdump` and the app's debug log.
public enum LinkEvent: Sendable {
    case sent([UInt8], note: String)
    case received([UInt8])
    case frame(Frame)
    case dropped([UInt8], reason: String)
}

/// Request/response over a `PacketLink`: docs/protocol.md §3.
/// - The reply is the next inbound frame with the same command (for writes, the ACK).
/// - Resend after 0.5 s, then 1 s, then 1.5 s, then give up.
/// - Any other inbound frame is a push and goes to `onPush`.
/// - One exchange at a time; later callers wait their turn.
@MainActor
public final class PacketSession {
    public static let retryTimeouts: [Duration] = [.milliseconds(500), .milliseconds(1000), .milliseconds(1500)]
    /// Multi-packet replies (`0B 01`): per-packet timeout and packet limit (§3 rule 7).
    public static let multiPacketTimeout: Duration = .seconds(2)
    public static let multiPacketLimit = 20

    private struct Waiter {
        let id: Int
        let command: Command
        let continuation: CheckedContinuation<Frame?, Never>
    }

    private let link: any PacketLink
    private var decoder = FrameDecoder(expecting: .deviceToHost)
    private var waiter: Waiter?
    private var nextWaiterID = 0
    private let gate = SerialGate()

    public var onPush: ((Frame) -> Void)?
    public var onClose: (() -> Void)?
    public var onEvent: ((LinkEvent) -> Void)?

    public init(link: any PacketLink) {
        self.link = link
        link.onReceive = { [weak self] bytes in self?.receive(bytes) }
        link.onClose = { [weak self] in self?.linkClosed() }
    }

    public var isOpen: Bool { link.isOpen }

    public func close() async {
        await link.close()
        resolveWaiter(id: nil, with: nil)
    }

    // MARK: Exchanges

    /// Sends `frame` and returns the inbound frame with the same command (the reply, or for a
    /// write, its ACK).
    public func exchange(_ frame: Frame) async throws(SoundcoreError) -> Frame {
        await gate.lock()
        defer { gate.unlock() }
        return try await sendAndAwait(frame)
    }

    /// Sends `frame` without waiting for anything (§7.2 fire-and-forget writes).
    public func sendWithoutReply(_ frame: Frame) async throws(SoundcoreError) {
        await gate.lock()
        defer { gate.unlock() }
        try write(frame, note: describe(frame))
    }

    /// `01 01` → parsed state.
    public func readState() async throws(SoundcoreError) -> D1202State {
        let reply = try await exchange(Requests.requestState())
        do {
            return try D1202State(body: reply.body)
        } catch {
            throw .parse(error)
        }
    }

    /// `0B 01` → the full device list, collected over as many packets as the earbuds send.
    public func readDualConnectionDevices() async throws(SoundcoreError) -> [DualConnectionDevice] {
        await gate.lock()
        defer { gate.unlock() }
        var frame = try await sendAndAwait(Requests.requestDualConnectionDevices())
        var devices: [DualConnectionDevice] = []
        for _ in 0..<Self.multiPacketLimit {
            let packet: DualConnectionPacket
            do {
                packet = try DualConnectionPacket(body: frame.body)
            } catch {
                throw .parse(error)
            }
            if packet.index <= 1 { devices = [] }
            devices += packet.devices
            if packet.isLast { break }
            guard let next = await awaitFrame(.dualConnectionDevices, timeout: Self.multiPacketTimeout) else { break }
            frame = next
        }
        return devices
    }

    private func sendAndAwait(_ frame: Frame) async throws(SoundcoreError) -> Frame {
        for (attempt, timeout) in Self.retryTimeouts.enumerated() {
            var note = describe(frame)
            if attempt > 0 { note += ", retry \(attempt)" }
            try write(frame, note: note)
            if let reply = await awaitFrame(frame.command, timeout: timeout) { return reply }
            guard link.isOpen else { throw .channelClosed }
        }
        throw .timeout(frame.command)
    }

    private func write(_ frame: Frame, note: String) throws(SoundcoreError) {
        let bytes = frame.encoded()
        onEvent?(.sent(bytes, note: note))
        try link.write(bytes)
    }

    private func describe(_ frame: Frame) -> String {
        frame.command.name.map { "\(frame.command) \($0)" } ?? "\(frame.command)"
    }

    // MARK: Inbound

    private func awaitFrame(_ command: Command, timeout: Duration) async -> Frame? {
        guard link.isOpen else { return nil }
        nextWaiterID += 1
        let id = nextWaiterID
        return await withCheckedContinuation { continuation in
            waiter = Waiter(id: id, command: command, continuation: continuation)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resolveWaiter(id: id, with: nil)
            }
        }
    }

    /// Resumes the current waiter (only if its id matches, when given).
    private func resolveWaiter(id: Int?, with frame: Frame?) {
        guard let current = waiter, id == nil || current.id == id else { return }
        waiter = nil
        current.continuation.resume(returning: frame)
    }

    private func receive(_ bytes: [UInt8]) {
        onEvent?(.received(bytes))
        for event in decoder.feed(bytes) {
            switch event {
            case let .frame(frame):
                onEvent?(.frame(frame))
                if let current = waiter, current.command == frame.command {
                    resolveWaiter(id: current.id, with: frame)
                } else {
                    onPush?(frame)
                }
            case let .discarded(dropped, reason):
                onEvent?(.dropped(dropped, reason: reason))
            }
        }
    }

    private func linkClosed() {
        resolveWaiter(id: nil, with: nil)
        onClose?()
    }
}

/// A FIFO async mutex for main-actor code.
@MainActor
final class SerialGate {
    private var locked = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if locked {
            // unlock() hands the lock straight to us, so `locked` stays true.
            await withCheckedContinuation { waiting.append($0) }
        } else {
            locked = true
        }
    }

    func unlock() {
        if waiting.isEmpty {
            locked = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
