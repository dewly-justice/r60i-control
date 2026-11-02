// Frame format: docs/protocol.md §2.
//
//   prefix(5) | command(2) | total length (u16 LE) | body | checksum(1)
//
// The length counts every byte of the frame. The checksum is the 8-bit wrapping sum of all
// bytes before it.

/// Which way a frame travels. Each direction has its own fixed 5-byte prefix.
public enum Direction: Sendable, Hashable {
    case hostToDevice
    case deviceToHost

    public var prefix: [UInt8] {
        switch self {
        case .hostToDevice: [0x08, 0xEE, 0x00, 0x00, 0x00]
        case .deviceToHost: [0x09, 0xFF, 0x00, 0x00, 0x01]
        }
    }
}

/// Two-byte command identifier, written as `[group, id]`.
public struct Command: Hashable, Sendable, CustomStringConvertible {
    public let group: UInt8
    public let id: UInt8

    public init(_ group: UInt8, _ id: UInt8) {
        self.group = group
        self.id = id
    }

    public var description: String { [group, id].hexString }
}

extension Command {
    // Device → host (replies and pushes), docs/protocol.md §6.
    public static let state = Command(0x01, 0x01)
    public static let twsStatus = Command(0x01, 0x02)
    public static let batteryLevel = Command(0x01, 0x03)
    public static let batteryCharging = Command(0x01, 0x04)
    public static let firmwareAndSerial = Command(0x01, 0x05)
    public static let ldacState = Command(0x01, 0x7F)
    public static let soundModes = Command(0x06, 0x01)
    public static let dualConnectionDevices = Command(0x0B, 0x01)

    // Host → device writes, docs/protocol.md §7.2. Only the ones implemented so far.
    public static let setSoundModes = Command(0x06, 0x81)

    /// Human-readable label for logs. `nil` for commands we have no name for.
    public var name: String? {
        switch self {
        case .state: "state"
        case .twsStatus: "TWS status"
        case .batteryLevel: "battery level"
        case .batteryCharging: "battery charging"
        case .firmwareAndSerial: "firmware + serial"
        case .ldacState: "LDAC"
        case .soundModes: "sound modes"
        case .dualConnectionDevices: "dual-connection devices"
        case .setSoundModes: "set sound modes"
        default: nil
        }
    }
}

public enum Checksum {
    public static func compute<S: Sequence<UInt8>>(_ bytes: S) -> UInt8 {
        bytes.reduce(0, &+)
    }
}

public struct Frame: Hashable, Sendable {
    /// prefix + command + length
    public static let headerLength = 9
    /// header + checksum
    public static let overhead = 10

    public var direction: Direction
    public var command: Command
    public var body: [UInt8]

    public init(_ direction: Direction, _ command: Command, body: [UInt8] = []) {
        self.direction = direction
        self.command = command
        self.body = body
    }

    /// Full on-the-wire bytes, including checksum.
    public func encoded() -> [UInt8] {
        let length = UInt16(Self.overhead + body.count)
        var bytes = direction.prefix
        bytes.reserveCapacity(Int(length))
        bytes += [command.group, command.id, UInt8(length & 0xFF), UInt8(length >> 8)]
        bytes += body
        bytes.append(Checksum.compute(bytes))
        return bytes
    }
}
