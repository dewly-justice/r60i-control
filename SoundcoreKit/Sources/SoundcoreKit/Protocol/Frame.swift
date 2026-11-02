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

    // Host → device writes used by the D1202 module, docs/protocol.md §7.2.
    // Never add a command here without a cited byte layout in that table.
    public static let setSoundModes = Command(0x06, 0x81)
    public static let setSoundModeCycle = Command(0x06, 0x82)
    public static let setEqualizer = Command(0x03, 0x87)
    public static let setSpatialAudio = Command(0x10, 0x81)
    public static let setButtonAction = Command(0x04, 0x81)
    public static let resetButtons = Command(0x04, 0x82)
    public static let setVolumeLimit = Command(0x20, 0x82)
    public static let setVolumeLimitRefreshRate = Command(0x20, 0x81)
    public static let setDualConnections = Command(0x0B, 0x84)
    public static let forgetDualConnectionDevice = Command(0x0B, 0x83)
    public static let connectDualConnectionDevice = Command(0x0B, 0x82)
    public static let disconnectDualConnectionDevice = Command(0x0B, 0x81)
    public static let setAutoPowerOff = Command(0x01, 0x86)
    public static let setTouchTone = Command(0x01, 0x83)
    public static let setLowBatteryPrompt = Command(0x10, 0x82)
    public static let setLDAC = Command(0x01, 0xFF)

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
        case .setSoundModeCycle: "set sound-mode cycle"
        case .setEqualizer: "set equalizer"
        case .setSpatialAudio: "set spatial audio"
        case .setButtonAction: "set button action"
        case .resetButtons: "reset buttons"
        case .setVolumeLimit: "set volume limit"
        case .setVolumeLimitRefreshRate: "set dB refresh rate"
        case .setDualConnections: "set dual connections"
        case .forgetDualConnectionDevice: "forget device"
        case .connectDualConnectionDevice: "connect device"
        case .disconnectDualConnectionDevice: "disconnect device"
        case .setAutoPowerOff: "set auto power-off"
        case .setTouchTone: "set touch tone"
        case .setLowBatteryPrompt: "set low-battery prompt"
        case .setLDAC: "set LDAC"
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
