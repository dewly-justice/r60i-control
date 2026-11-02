// Equalizer encoding and presets: docs/protocol.md §5, §7.3, §8.6.
// Each band byte = tenths of a dB + 120 (120 = 0.0 dB, 0 = −12.0 dB, 254 = +13.4 dB).
// A channel whose first byte is 0xFF is absent.

public struct EqualizerConfiguration: Hashable, Sendable {
    public static let bandCount = 10
    public static let visibleBandCount = 8
    public static let visibleBandFrequencies = [100, 200, 400, 800, 1600, 3200, 6400, 12800]
    public static let customPresetID: UInt16 = 0xFEFE

    /// preset id (2, LE) + left (10) + right (10)
    public var raw: [UInt8]

    public init(raw: [UInt8]) {
        precondition(raw.count == 2 + 2 * Self.bandCount)
        self.raw = raw
    }

    public var presetID: UInt16 { UInt16(raw[0]) | UInt16(raw[1]) << 8 }

    public var preset: EqualizerPreset? { EqualizerPreset.all.first { $0.id == presetID } }

    public var presetName: String {
        if presetID == Self.customPresetID { return "Custom" }
        return preset?.name ?? "unknown preset \(presetID)"
    }

    /// Band bytes, or nil if the channel is absent.
    public var leftBytes: [UInt8]? { channel(at: 2) }
    public var rightBytes: [UInt8]? { channel(at: 2 + Self.bandCount) }

    /// Values in tenths of a dB, or nil if the channel is absent.
    public var left: [Int]? { leftBytes?.map(Self.tenthsOfDecibel) }
    public var right: [Int]? { rightBytes?.map(Self.tenthsOfDecibel) }

    public static func tenthsOfDecibel(_ byte: UInt8) -> Int { Int(byte) - 120 }

    private func channel(at offset: Int) -> [UInt8]? {
        let bytes = Array(raw[offset..<(offset + Self.bandCount)])
        return bytes[0] == 0xFF ? nil : bytes
    }
}

public struct EqualizerPreset: Hashable, Sendable {
    public let id: UInt16
    public let name: String
    /// 10 values in tenths of a dB (8 visible bands, then the two hidden ones).
    public let values: [Int]

    /// OpenSCQ30 `lib/src/devices/soundcore/common/modules/equalizer.rs` (`common_settings_type_2`).
    public static let all: [EqualizerPreset] = [
        .init(id: 0, name: "Soundcore Signature", values: [0, 0, 0, 0, 0, 0, 0, 0, 0, -120]),
        .init(id: 1, name: "Acoustic", values: [40, 10, 20, 20, 40, 40, 40, 20, 0, -120]),
        .init(id: 2, name: "Bass Booster", values: [40, 30, 10, 0, 0, 0, 0, 0, 0, -120]),
        .init(id: 3, name: "Bass Reducer", values: [-40, -30, -10, 0, 0, 0, 0, 0, 0, -120]),
        .init(id: 4, name: "Classical", values: [30, 30, -20, -20, 0, 20, 30, 40, 0, -120]),
        .init(id: 5, name: "Podcast", values: [-30, 20, 40, 40, 30, 20, 0, -20, 0, -120]),
        .init(id: 6, name: "Dance", values: [20, -30, -10, 10, 20, 20, 10, -30, 0, -120]),
        .init(id: 7, name: "Deep", values: [20, 10, 30, 30, 20, -20, -40, -50, 0, -120]),
        .init(id: 8, name: "Electronic", values: [30, 20, -20, 20, 10, 20, 30, 30, 0, -120]),
        .init(id: 9, name: "Flat", values: [-20, -20, -10, 0, 0, 0, -20, -20, 0, -120]),
        .init(id: 10, name: "Hip-Hop", values: [20, 30, -10, -10, 20, -10, 20, 30, 0, -120]),
        .init(id: 11, name: "Jazz", values: [20, 20, -20, -20, 0, 20, 30, 40, 0, -120]),
        .init(id: 12, name: "Latin", values: [0, 0, -20, -20, -20, 0, 30, 50, 0, -120]),
        .init(id: 13, name: "Lounge", values: [-10, 20, 40, 30, 0, -20, 20, 10, 0, -120]),
        .init(id: 14, name: "Piano", values: [0, 30, 30, 20, 40, 50, 30, 40, 0, -120]),
        .init(id: 15, name: "Pop", values: [-10, 10, 30, 30, 10, -10, -20, -30, 0, -120]),
        .init(id: 16, name: "R&B", values: [60, 20, -20, -20, 20, 30, 30, 40, 0, -120]),
        .init(id: 17, name: "Rock", values: [30, 20, -10, -10, 10, 30, 40, 50, 0, -120]),
        .init(id: 18, name: "Small Speakers", values: [40, 30, 10, 0, -20, -30, -40, -40, 0, -120]),
        .init(id: 19, name: "Spoken Word", values: [-30, -20, 10, 20, 20, 10, 0, -30, 0, -120]),
        .init(id: 20, name: "Treble Booster", values: [-20, -20, -20, -10, 10, 20, 20, 40, 0, -120]),
        .init(id: 21, name: "Treble Reducer", values: [0, 0, 0, -20, -30, -40, -40, -60, 0, -120]),
    ]
}

// MARK: - Writing (§7.3, §7.4)

extension EqualizerConfiguration {
    public static let decibelTenthsRange = -120...134

    /// Band byte for a value in tenths of a dB, clamped to the encodable range.
    public static func byte(forTenths tenths: Int) -> UInt8 {
        UInt8(min(max(tenths, decibelTenthsRange.lowerBound), decibelTenthsRange.upperBound) + 120)
    }

    public init(presetID: UInt16, left: [UInt8], right: [UInt8]) {
        self.init(raw: [UInt8(presetID & 0xFF), UInt8(presetID >> 8)] + left + right)
    }
}

/// The 48-byte HearID block of the state packet (offset 0x3D), in state-packet order:
/// enabled(1) · left(10) · right(10) · timestamp u32 BE(4) · type(1) · custom left(10) ·
/// custom right(10) · favorite genre u16 LE(2). We never edit HearID; we only echo it back.
public struct HearIDBlock: Hashable, Sendable {
    public static let byteCount = 48
    public var raw: [UInt8]

    public init(raw: [UInt8]) {
        precondition(raw.count == Self.byteCount)
        self.raw = raw
    }

    public var isEnabled: Bool { raw[0] == 1 }
    public var left: [UInt8] { Self.channel(raw[1..<11]) }
    public var right: [UInt8] { Self.channel(raw[11..<21]) }
    public var timestamp: [UInt8] { Array(raw[21..<25]) }
    public var typeRaw: UInt8 { raw[25] }
    public var customLeft: [UInt8] { Self.channel(raw[26..<36]) }
    public var customRight: [UInt8] { Self.channel(raw[36..<46]) }
    public var favoriteGenre: [UInt8] { Array(raw[46..<48]) }

    /// OpenSCQ30 treats a channel whose first byte is 0xFF as absent and writes it as FF×10.
    static func channel(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
        bytes.first == 0xFF ? Array(repeating: 0xFF, count: bytes.count) : Array(bytes)
    }
}

/// Body of a `03 87` set-equalizer write (D1202 layout, 114 bytes), docs/protocol.md §7.3.
///
/// Matches OpenSCQ30 `sc/d1202/packets/outbound.rs` (`set_equalizer_configuration`), with one
/// deliberate difference: the HearID type byte is echoed as the earbuds reported it. A real
/// R60i NC that never ran HearID reports 0xFF, which OpenSCQ30 would rewrite to 0.
public struct EqualizerWrite: Hashable, Sendable {
    public var presetID: UInt16
    /// 10 band bytes per channel.
    public var left: [UInt8]
    public var right: [UInt8]
    public var hearID: HearIDBlock
    /// An EQ change turns HearID off (OpenSCQ30 sets `is_enabled = false`). The spatial-audio-off
    /// packet keeps the HearID enabled flag as it is.
    public var turnsHearIDOff: Bool

    public init(presetID: UInt16, left: [UInt8], right: [UInt8], hearID: HearIDBlock, turnsHearIDOff: Bool) {
        precondition(left.count == EqualizerConfiguration.bandCount && right.count == EqualizerConfiguration.bandCount)
        self.presetID = presetID
        self.left = left
        self.right = right
        self.hearID = hearID
        self.turnsHearIDOff = turnsHearIDOff
    }

    /// Select a preset: its 10 values go to both channels (§7.3).
    public static func preset(_ preset: EqualizerPreset, hearID: HearIDBlock) -> EqualizerWrite {
        let bytes = preset.values.map(EqualizerConfiguration.byte(forTenths:))
        return EqualizerWrite(presetID: preset.id, left: bytes, right: bytes, hearID: hearID, turnsHearIDOff: true)
    }

    /// Custom EQ: 8 visible bands in tenths of a dB; the two hidden bands are 0 dB. Both channels
    /// get the same values (§7.3).
    public static func custom(_ visibleBands: [Int], hearID: HearIDBlock) -> EqualizerWrite {
        precondition(visibleBands.count == EqualizerConfiguration.visibleBandCount)
        let bytes = (visibleBands + [0, 0]).map(EqualizerConfiguration.byte(forTenths:))
        return EqualizerWrite(
            presetID: EqualizerConfiguration.customPresetID, left: bytes, right: bytes,
            hearID: hearID, turnsHearIDOff: true
        )
    }

    /// The packet that turns spatial audio off (§7.4): current preset ID, channel 1's values on
    /// both channels (0 dB if absent), hidden band 9 = 0 dB, hidden band 10 = −12.0 dB.
    public static func spatialAudioOff(current: EqualizerConfiguration, hearID: HearIDBlock) -> EqualizerWrite {
        var bytes = current.leftBytes ?? Array(repeating: 120, count: EqualizerConfiguration.bandCount)
        bytes[8] = EqualizerConfiguration.byte(forTenths: 0)
        bytes[9] = EqualizerConfiguration.byte(forTenths: -120)
        return EqualizerWrite(presetID: current.presetID, left: bytes, right: bytes, hearID: hearID, turnsHearIDOff: false)
    }

    public var hearIDEnabledAfterWrite: Bool { turnsHearIDOff ? false : hearID.isEnabled }

    public var body: [UInt8] {
        let hearIDEnabled = hearIDEnabledAfterWrite
        var body: [UInt8] = [UInt8(presetID & 0xFF), UInt8(presetID >> 8)]
        body += hearID.favoriteGenre
        body += left + right
        body += [0, 0]
        body.append(hearIDEnabled ? 1 : 0)
        body += hearID.left + hearID.right
        body += hearID.timestamp
        body.append(hearID.typeRaw)
        body += hearID.customLeft + hearID.customRight
        let active: [UInt8] = if hearIDEnabled {
            hearID.typeRaw == 1 ? hearID.customLeft + hearID.customRight : hearID.left + hearID.right
        } else {
            left + right
        }
        for byte in active { body += [byte, 0] }
        body += [0, 0]
        return body
    }

    /// The equalizer the earbuds should report after this write.
    public var resultingConfiguration: EqualizerConfiguration {
        EqualizerConfiguration(presetID: presetID, left: left, right: right)
    }
}
