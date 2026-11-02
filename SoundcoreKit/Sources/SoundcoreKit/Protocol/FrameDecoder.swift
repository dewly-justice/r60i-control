// Stream reassembly: docs/protocol.md §3 rule 1.
//
// RFCOMM delivers a byte stream. One read may hold part of a frame or several frames.
// Append each read with `feed(_:)`; the decoder returns every complete frame it can parse.

public struct FrameDecoder: Sendable {
    public enum Event: Hashable, Sendable {
        case frame(Frame)
        /// Bytes dropped because they could not start a valid frame.
        case discarded([UInt8], reason: String)
    }

    /// No D1202 frame comes close to this. A larger length field means we lost sync.
    public static let maximumFrameLength = 2048

    public let direction: Direction
    public private(set) var buffer: [UInt8] = []

    public init(expecting direction: Direction = .deviceToHost) {
        self.direction = direction
    }

    public mutating func feed<S: Sequence<UInt8>>(_ bytes: S) -> [Event] {
        buffer.append(contentsOf: bytes)
        var events: [Event] = []
        while let event = nextEvent() {
            events.append(event)
        }
        return events
    }

    private mutating func nextEvent() -> Event? {
        guard !buffer.isEmpty else { return nil }

        let prefix = direction.prefix
        let comparable = min(buffer.count, prefix.count)
        guard buffer[0..<comparable].elementsEqual(prefix[0..<comparable]) else {
            return discardUntilNextPrefix(reason: "unexpected prefix")
        }
        guard buffer.count >= Frame.headerLength else { return nil }

        let length = Int(buffer[7]) | Int(buffer[8]) << 8
        guard length >= Frame.overhead, length <= Self.maximumFrameLength else {
            return discardUntilNextPrefix(reason: "implausible length field \(length)")
        }
        guard buffer.count >= length else { return nil }

        let expected = Checksum.compute(buffer[0..<(length - 1)])
        guard expected == buffer[length - 1] else {
            return discardUntilNextPrefix(
                reason: "checksum mismatch (got \([buffer[length - 1]].hexString), expected \([expected].hexString))"
            )
        }

        let frame = Frame(
            direction,
            Command(buffer[5], buffer[6]),
            body: Array(buffer[Frame.headerLength..<(length - 1)])
        )
        buffer.removeFirst(length)
        return .frame(frame)
    }

    /// Drop bytes up to the next place a frame could start. OpenSCQ30 clears the whole buffer
    /// here; resyncing on the next prefix byte recovers at least as well.
    private mutating func discardUntilNextPrefix(reason: String) -> Event {
        let first = direction.prefix[0]
        let next = buffer.indices.dropFirst().first(where: { buffer[$0] == first }) ?? buffer.endIndex
        let dropped = Array(buffer[..<next])
        buffer.removeFirst(next)
        return .discarded(dropped, reason: reason)
    }
}
