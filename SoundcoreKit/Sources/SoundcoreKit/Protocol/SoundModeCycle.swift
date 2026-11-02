// Which sound modes "Switch Sound Mode" (press and hold, by default) cycles through.
// docs/protocol.md §6.10 and §7.2 (`06 82`).
//
// OpenSCQ30's D1202 module skips this byte (state offset 0x76) as unknown. The layout is OpenSCQ30's
// `AmbientSoundModeCycleTws` (`sc/common/structures/ambient_sound_mode_cycle.rs`), which the A3968
// reads from the same place: its state packet matches D1202's up to the sound-modes block, with the
// cycle byte right after the buttons (`sc/a3968/packets/inbound/state_update.rs:92-96`). The write is
// `set_ambient_sound_mode_cycle_tws` (`sc/common/packet/outbound/set_ambient_sound_mode_cycle.rs:24`).
// Soundcore documents the setting for the R60i NC ("You can add Normal mode via the app").

/// The modes in one cycle: one nibble, bit 0 Noise Cancelling, bit 1 Transparency, bit 2 Normal.
public struct SoundModeCycle: Hashable, Sendable {
    public static let noiseCancelingBit: UInt8 = 1 << 0
    public static let transparencyBit: UInt8 = 1 << 1
    public static let normalBit: UInt8 = 1 << 2

    /// The nibble as the earbuds reported it. Bit 3 isn't documented and is sent back unchanged.
    public private(set) var nibble: UInt8

    public init(nibble: UInt8) {
        self.nibble = nibble & 0x0F
    }

    public static func bit(for mode: AmbientSoundMode) -> UInt8 {
        switch mode {
        case .noiseCanceling: noiseCancelingBit
        case .transparency: transparencyBit
        case .normal: normalBit
        }
    }

    public func contains(_ mode: AmbientSoundMode) -> Bool {
        nibble & Self.bit(for: mode) != 0
    }

    /// The modes in the cycle, in the order the earbuds step through them.
    public var modes: [AmbientSoundMode] {
        [.noiseCanceling, .transparency, .normal].filter(contains)
    }

    public func setting(_ mode: AmbientSoundMode, included: Bool) -> SoundModeCycle {
        var copy = self
        if included {
            copy.nibble |= Self.bit(for: mode)
        } else {
            copy.nibble &= ~Self.bit(for: mode)
        }
        return copy
    }
}

/// The cycle while both earbuds are in use (low nibble) and while only one is (high nibble).
public struct SoundModeCycles: Hashable, Sendable {
    public var raw: UInt8

    public init(raw: UInt8) {
        self.raw = raw
    }

    public var twoEarbuds: SoundModeCycle { SoundModeCycle(nibble: raw & 0x0F) }
    public var oneEarbud: SoundModeCycle { SoundModeCycle(nibble: raw >> 4) }

    /// The cycle that applies now. As with the buttons, the earbuds keep one for each situation.
    public func current(budsLinked: Bool) -> SoundModeCycle {
        budsLinked ? twoEarbuds : oneEarbud
    }

    public func replacing(_ cycle: SoundModeCycle, budsLinked: Bool) -> SoundModeCycles {
        budsLinked
            ? SoundModeCycles(raw: (raw & 0xF0) | cycle.nibble)
            : SoundModeCycles(raw: (cycle.nibble << 4) | (raw & 0x0F))
    }
}
