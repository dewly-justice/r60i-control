// The D1202/D1202C full state packet (`01 01` body): docs/protocol.md §6.1.
// Parse order follows OpenSCQ30 `lib/src/devices/soundcore/d1202/packets/inbound/state_update.rs`.
//
// Parsing is deliberately lenient: every field keeps its raw bytes, and unknown values are kept
// as-is rather than replaced with defaults. Writing is strict (see SoundModes.encodedForWrite).

public enum D1202StateLayout {
    public static let twsHostDevice = 0x00
    public static let twsConnected = 0x01
    public static let batteryLeft = 0x02
    public static let batteryRight = 0x03
    public static let chargingLeft = 0x04
    public static let chargingRight = 0x05
    public static let firmwareLeft = 0x06 // 5
    public static let firmwareRight = 0x0B // 5
    public static let serialNumber = 0x10 // 16
    public static let unknownCaseFirmware = 0x20 // 5
    public static let caseBattery = 0x25
    public static let equalizer = 0x26 // 2 + 10 + 10
    public static let unknown3C = 0x3C
    public static let hearID = 0x3D // 48
    public static let unknown6D = 0x6D
    public static let buttons = 0x6E // 8
    public static let unknown76 = 0x76
    public static let soundModes = 0x77 // 8
    public static let unknown7F = 0x7F
    public static let touchTone = 0x80
    public static let lowBatteryPrompt = 0x81
    public static let ldac = 0x82
    public static let dualConnections = 0x83
    public static let autoPowerOff = 0x84 // 2
    public static let volumeLimit = 0x86 // 3
    public static let spatialAudio = 0x89 // 2
    /// Bytes OpenSCQ30 parses. Real packets carry more; extra bytes are kept in `body`.
    public static let minimumBodyLength = 0x8B
}

public struct D1202State: Hashable, Sendable {
    /// The complete packet body, including trailing bytes nobody parses yet.
    public let body: [UInt8]

    public var tws: TWSStatus
    public var leftBattery: EarbudBattery
    public var rightBattery: EarbudBattery
    public var caseBattery: BatteryLevel
    public var firmwareLeft: FirmwareVersion
    public var firmwareRight: FirmwareVersion
    public var serialNumber: String
    public var equalizer: EqualizerConfiguration
    /// HearID block, 48 bytes from offset 0x3D. Only echoed back in EQ writes (Phase 2).
    public var hearID: [UInt8]
    public var buttons: ButtonConfiguration
    public var soundModes: SoundModes
    public var touchTone: Bool
    public var lowBatteryPrompt: Bool
    public var ldac: Bool
    public var dualConnections: Bool
    public var autoPowerOff: AutoPowerOff
    public var volumeLimit: VolumeLimit
    public var spatialAudio: SpatialAudio

    public init(body: [UInt8]) throws(ParseError) {
        typealias L = D1202StateLayout
        guard body.count >= L.minimumBodyLength else {
            throw .tooShort(what: "D1202 state", needed: L.minimumBodyLength, got: body.count)
        }
        func slice(_ offset: Int, _ count: Int) -> [UInt8] { Array(body[offset..<(offset + count)]) }
        func flag(_ offset: Int) -> Bool { body[offset] == 1 }

        self.body = body
        tws = TWSStatus(hostDeviceRaw: body[L.twsHostDevice], isConnected: flag(L.twsConnected))
        leftBattery = EarbudBattery(level: BatteryLevel(raw: body[L.batteryLeft]), isCharging: flag(L.chargingLeft))
        rightBattery = EarbudBattery(level: BatteryLevel(raw: body[L.batteryRight]), isCharging: flag(L.chargingRight))
        caseBattery = BatteryLevel(raw: body[L.caseBattery])
        firmwareLeft = FirmwareVersion(raw: slice(L.firmwareLeft, 5))
        firmwareRight = FirmwareVersion(raw: slice(L.firmwareRight, 5))
        serialNumber = Self.ascii(slice(L.serialNumber, 16))
        equalizer = EqualizerConfiguration(raw: slice(L.equalizer, 22))
        hearID = slice(L.hearID, 48)
        buttons = ButtonConfiguration(raw: slice(L.buttons, 8))
        soundModes = try SoundModes(bytes: slice(L.soundModes, SoundModes.byteCount))
        touchTone = flag(L.touchTone)
        lowBatteryPrompt = flag(L.lowBatteryPrompt)
        ldac = flag(L.ldac)
        dualConnections = flag(L.dualConnections)
        autoPowerOff = AutoPowerOff(isEnabled: flag(L.autoPowerOff), durationIndex: body[L.autoPowerOff + 1])
        volumeLimit = VolumeLimit(
            isEnabled: flag(L.volumeLimit),
            decibels: body[L.volumeLimit + 1],
            refreshRateRaw: body[L.volumeLimit + 2]
        )
        spatialAudio = SpatialAudio(isEnabled: flag(L.spatialAudio), modeRaw: body[L.spatialAudio + 1])
    }

    /// The serial number is ASCII alphanumerics. Anything else is shown as hex.
    static func ascii(_ bytes: [UInt8]) -> String {
        let isAlphanumeric = bytes.allSatisfy { (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) }
        return isAlphanumeric ? String(decoding: bytes, as: UTF8.self) : "<\(bytes.hexString)>"
    }
}

// MARK: - TWS / battery / firmware (§5)

public struct TWSStatus: Hashable, Sendable {
    /// 0 = left, 1 = right
    public var hostDeviceRaw: UInt8
    /// The two earbuds are linked to each other.
    public var isConnected: Bool

    public var hostDeviceName: String {
        switch hostDeviceRaw {
        case 0: "left"
        case 1: "right"
        default: "unknown (\(hostDeviceRaw))"
        }
    }
}

public struct BatteryLevel: Hashable, Sendable {
    public var raw: UInt8

    public init(raw: UInt8) { self.raw = raw }

    /// 255 means not present (bud not linked, or case unavailable).
    public var isAvailable: Bool { raw != 0xFF }

    /// Raw 0…9 shown as 10…100 % (OpenSCQ30: max level 10, offset 1).
    public var percent: Int? { isAvailable ? (Int(raw) + 1) * 10 : nil }
}

public struct EarbudBattery: Hashable, Sendable {
    public var level: BatteryLevel
    public var isCharging: Bool
}

public struct FirmwareVersion: Hashable, Sendable {
    public var raw: [UInt8]

    /// All zeros or all 0xFF means this side didn't report a version.
    public var isAvailable: Bool {
        !(raw.allSatisfy { $0 == 0x00 } || raw.allSatisfy { $0 == 0xFF })
    }

    /// `"01.83"`, or hex if the bytes are not the expected `DD.DD` ASCII.
    public var displayString: String? {
        guard isAvailable else { return nil }
        let isDigit: (UInt8) -> Bool = { (0x30...0x39).contains($0) }
        let wellFormed = raw.count == 5 && isDigit(raw[0]) && isDigit(raw[1]) && raw[2] == 0x2E && isDigit(raw[3]) && isDigit(raw[4])
        return wellFormed ? String(decoding: raw, as: UTF8.self) : "<\(raw.hexString)>"
    }
}

// MARK: - Misc settings (§6.1, §8.5, §8.8, §8.9)

public struct AutoPowerOff: Hashable, Sendable {
    public static let durationsMinutes = [10, 20, 30, 60]

    public var isEnabled: Bool
    public var durationIndex: UInt8

    public var minutes: Int? {
        Self.durationsMinutes.indices.contains(Int(durationIndex)) ? Self.durationsMinutes[Int(durationIndex)] : nil
    }
}

public struct VolumeLimit: Hashable, Sendable {
    public var isEnabled: Bool
    public var decibels: UInt8
    public var refreshRateRaw: UInt8

    public var refreshRateName: String {
        switch refreshRateRaw {
        case 0: "real time"
        case 1: "10 s"
        case 2: "1 min"
        default: "unknown (\(refreshRateRaw))"
        }
    }
}

public enum SpatialAudioMode: UInt8, Sendable, CaseIterable {
    case music = 0
    case movie = 2
    case gaming = 3

    public var displayName: String {
        switch self {
        case .music: "Music"
        case .movie: "Movie"
        case .gaming: "Gaming"
        }
    }
}

public struct SpatialAudio: Hashable, Sendable {
    public var isEnabled: Bool
    public var modeRaw: UInt8
    public var mode: SpatialAudioMode? { SpatialAudioMode(rawValue: modeRaw) }
}
