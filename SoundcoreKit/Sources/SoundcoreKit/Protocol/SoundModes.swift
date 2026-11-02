// The D1202 8-byte sound-modes block: docs/protocol.md §6.2.
// It appears at state offset 0x77, is the whole body of the `06 01` push, and is the whole
// body of the `06 81` write.
//
// Encoding mirrors OpenSCQ30 `lib/src/devices/soundcore/d1202/structures.rs` (SoundModes::bytes).

public enum AmbientSoundMode: UInt8, Sendable, CaseIterable, Identifiable {
    public var id: UInt8 { rawValue }

    case noiseCanceling = 0
    case transparency = 1
    case normal = 2

    public var displayName: String {
        switch self {
        case .noiseCanceling: "Noise Canceling"
        case .transparency: "Transparency"
        case .normal: "Normal"
        }
    }
}

public enum NoiseCancelingMode: UInt8, Sendable, CaseIterable, Identifiable {
    public var id: UInt8 { rawValue }

    case manual = 0
    case adaptive = 1
    case multiScene = 2

    public var displayName: String {
        switch self {
        case .manual: "Manual"
        case .adaptive: "Adaptive"
        case .multiScene: "Multi-scene"
        }
    }
}

public enum TransparencyMode: UInt8, Sendable, CaseIterable, Identifiable {
    public var id: UInt8 { rawValue }

    case fullyTransparent = 0
    case vocalMode = 1

    public var displayName: String {
        switch self {
        case .fullyTransparent: "Fully transparent"
        case .vocalMode: "Vocal mode"
        }
    }
}

public enum MultiSceneMode: UInt8, Sendable, CaseIterable, Identifiable {
    public var id: UInt8 { rawValue }

    case transport = 0
    case outdoor = 1
    case indoor = 2

    public var displayName: String {
        switch self {
        case .transport: "Transport"
        case .outdoor: "Outdoor"
        case .indoor: "Indoor"
        }
    }
}

public enum AdaptiveStrength: UInt8, Sendable, CaseIterable {
    case weak = 0
    case moderate = 1
    case strong = 2

    public var displayName: String {
        switch self {
        case .weak: "Weak"
        case .moderate: "Moderate"
        case .strong: "Strong"
        }
    }
}

public struct SoundModes: Hashable, Sendable {
    public static let byteCount = 8
    public static let manualLevelRange: ClosedRange<UInt8> = 1...5

    /// The 8 bytes exactly as the device sent them. Typed accessors read from and write to this array.
    public private(set) var raw: [UInt8]

    public init(bytes: some Collection<UInt8>) throws(ParseError) {
        guard bytes.count >= Self.byteCount else {
            throw ParseError.tooShort(what: "sound modes", needed: Self.byteCount, got: bytes.count)
        }
        raw = Array(bytes.prefix(Self.byteCount))
    }

    // MARK: Byte 0
    public var ambientRaw: UInt8 { raw[0] }
    public var ambient: AmbientSoundMode? {
        get { AmbientSoundMode(rawValue: raw[0]) }
        set { if let newValue { raw[0] = newValue.rawValue } }
    }

    // MARK: Byte 1 — high nibble manual level, low nibble adaptive strength (read-only)
    public var manualLevelRaw: UInt8 { raw[1] >> 4 }
    /// Manual ANC level 1…5. Setting it keeps the adaptive nibble as reported.
    public var manualLevel: Int {
        get { Int(manualLevelRaw) }
        set {
            let level = UInt8(min(max(newValue, Int(Self.manualLevelRange.lowerBound)), Int(Self.manualLevelRange.upperBound)))
            raw[1] = level << 4 | adaptiveStrengthRaw
        }
    }
    public var adaptiveStrengthRaw: UInt8 { raw[1] & 0x0F }
    public var adaptiveStrength: AdaptiveStrength? { AdaptiveStrength(rawValue: adaptiveStrengthRaw) }

    // MARK: Byte 2
    public var transparencyRaw: UInt8 { raw[2] }
    public var transparency: TransparencyMode? {
        get { TransparencyMode(rawValue: raw[2]) }
        set { if let newValue { raw[2] = newValue.rawValue } }
    }

    // MARK: Byte 3
    public var noiseCancelingModeRaw: UInt8 { raw[3] }
    public var noiseCancelingMode: NoiseCancelingMode? {
        get { NoiseCancelingMode(rawValue: raw[3]) }
        set { if let newValue { raw[3] = newValue.rawValue } }
    }

    // MARK: Byte 4 — bit 0 suppression enabled, bit 1 wind detected (read-only)
    public var windNoiseRaw: UInt8 { raw[4] }
    public var windNoiseSuppression: Bool {
        get { raw[4] & 0x01 != 0 }
        set { raw[4] = newValue ? raw[4] | 0x01 : raw[4] & ~0x01 }
    }
    public var windDetected: Bool { raw[4] & 0x02 != 0 }

    // MARK: Byte 5 — unknown
    public var unknownByte5: UInt8 { raw[5] }

    // MARK: Byte 6
    public var multiSceneRaw: UInt8 { raw[6] }
    public var multiScene: MultiSceneMode? {
        get { MultiSceneMode(rawValue: raw[6]) }
        set { if let newValue { raw[6] = newValue.rawValue } }
    }

    // MARK: Byte 7
    public var realTimeAdaptiveRaw: UInt8 { raw[7] }
    public var realTimeAdaptive: Bool {
        get { raw[7] == 1 }
        set { raw[7] = newValue ? 1 : 0 }
    }

    /// Bytes for a `06 81` write, encoded the way OpenSCQ30 does it:
    /// - enum fields are written as they are;
    /// - the manual level is clamped to 1…5;
    /// - only wind bits 0–1 are kept;
    /// - byte 5 is always 0;
    /// - byte 7 is 0 or 1.
    ///
    /// One deliberate difference: the adaptive-strength nibble (byte 1, low 4 bits) is read-only
    /// (OpenSCQ30 shows it as information and rejects setting it), so it is sent back exactly as
    /// the earbuds reported it. A real R60i NC reports 5, which OpenSCQ30's Weak/Moderate/Strong
    /// enum can't hold, so OpenSCQ30 would send 0 instead (docs/protocol.md §6.2).
    ///
    /// Throws if any other enum field holds a value OpenSCQ30 doesn't know. OpenSCQ30 would quietly
    /// replace it with a default. We refuse instead, so we never write a value the device didn't send.
    public func encodedForWrite() throws(EncodeError) -> [UInt8] {
        var unknown: [String] = []
        if ambient == nil { unknown.append("ambient mode = \(ambientRaw)") }
        if transparency == nil { unknown.append("transparency = \(transparencyRaw)") }
        if noiseCancelingMode == nil { unknown.append("noise-canceling mode = \(noiseCancelingModeRaw)") }
        if windNoiseRaw & ~0x03 != 0 { unknown.append("wind noise bits = \([windNoiseRaw].hexString)") }
        if multiScene == nil { unknown.append("multi-scene = \(multiSceneRaw)") }
        if realTimeAdaptiveRaw > 1 { unknown.append("real-time adaptive = \(realTimeAdaptiveRaw)") }
        guard unknown.isEmpty,
              let ambient, let transparency, let noiseCancelingMode, let multiScene
        else {
            throw EncodeError.unknownValues(unknown)
        }

        let manual = min(max(manualLevelRaw, Self.manualLevelRange.lowerBound), Self.manualLevelRange.upperBound)
        return [
            ambient.rawValue,
            manual << 4 | adaptiveStrengthRaw,
            transparency.rawValue,
            noiseCancelingMode.rawValue,
            windNoiseRaw & 0x03,
            0,
            multiScene.rawValue,
            realTimeAdaptive ? 1 : 0,
        ]
    }
}
