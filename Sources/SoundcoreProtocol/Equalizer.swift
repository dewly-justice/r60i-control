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
