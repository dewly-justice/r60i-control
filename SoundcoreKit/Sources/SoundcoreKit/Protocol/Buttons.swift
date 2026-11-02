// Touch controls: docs/protocol.md §5 (action byte) and §8.7.
// Each gesture byte: low nibble = action while the buds are linked, high nibble = action when
// one bud is used alone. 0xF = disabled.

public enum EarbudSide: UInt8, Sendable, CaseIterable, Identifiable {
    case left = 0
    case right = 1

    public var id: UInt8 { rawValue }
    public var displayName: String { self == .left ? "Left" : "Right" }
}

/// The four gestures, with OpenSCQ30's D1202 `button_id`s (`sc/d1202.rs:93-151`).
public enum GestureKind: Sendable, CaseIterable, Identifiable {
    case single, double, triple, long

    public var id: Self { self }

    public var buttonID: UInt8 {
        switch self {
        case .single: 2
        case .double: 0
        case .triple: 5
        case .long: 1
        }
    }

    public var displayName: String {
        switch self {
        case .single: "Single tap"
        case .double: "Double tap"
        case .triple: "Triple tap"
        case .long: "Press and hold"
        }
    }

    /// Actions OpenSCQ30 offers for this gesture on D1202. Single tap is limited to what the
    /// Soundcore app allows (§8.7).
    public var allowedActions: [ButtonAction] {
        switch self {
        case .single: [.volumeUp, .volumeDown, .previousTrack, .nextTrack, .playPause]
        case .double, .triple, .long: ButtonAction.allCases
        }
    }
}

public enum ButtonGesture: Int, Sendable, CaseIterable {
    // Order matches the state packet (offset 0x6E).
    case leftSingle, rightSingle, leftDouble, rightDouble, leftTriple, rightTriple, leftLong, rightLong

    public init(side: EarbudSide, kind: GestureKind) {
        let kindIndex = switch kind {
        case .single: 0
        case .double: 1
        case .triple: 2
        case .long: 3
        }
        self.init(rawValue: kindIndex * 2 + Int(side.rawValue))!
    }

    public var side: EarbudSide { rawValue % 2 == 0 ? .left : .right }

    public var kind: GestureKind {
        switch rawValue / 2 {
        case 0: .single
        case 1: .double
        case 2: .triple
        default: .long
        }
    }

    public var displayName: String {
        switch self {
        case .leftSingle: "Left single"
        case .rightSingle: "Right single"
        case .leftDouble: "Left double"
        case .rightDouble: "Right double"
        case .leftTriple: "Left triple"
        case .rightTriple: "Right triple"
        case .leftLong: "Left long"
        case .rightLong: "Right long"
        }
    }
}

public enum ButtonAction: UInt8, Sendable, CaseIterable, Identifiable {
    case volumeUp = 0
    case volumeDown = 1
    case previousTrack = 2
    case nextTrack = 3
    case ambientSoundMode = 4
    case voiceAssistant = 5
    case playPause = 6

    public static let disabledNibble: UInt8 = 0xF

    public var id: UInt8 { rawValue }

    public var displayName: String {
        switch self {
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .previousTrack: "Previous track"
        case .nextTrack: "Next track"
        case .ambientSoundMode: "Cycle sound mode"
        case .voiceAssistant: "Voice assistant"
        case .playPause: "Play/Pause"
        }
    }

    /// Display text for one nibble.
    public static func describe(nibble: UInt8) -> String {
        if nibble == disabledNibble { return "disabled" }
        return ButtonAction(rawValue: nibble)?.displayName ?? "unknown (\(nibble))"
    }
}

public struct ButtonConfiguration: Hashable, Sendable {
    public var raw: [UInt8]

    public init(raw: [UInt8]) {
        precondition(raw.count == ButtonGesture.allCases.count)
        self.raw = raw
    }

    public func linkedNibble(_ gesture: ButtonGesture) -> UInt8 { raw[gesture.rawValue] & 0x0F }
    public func soloNibble(_ gesture: ButtonGesture) -> UInt8 { raw[gesture.rawValue] >> 4 }

    /// The nibble that applies right now: the low ("linked") nibble while both buds are linked,
    /// the high ("solo") nibble when one bud is used alone (§8.7).
    public func currentNibble(_ gesture: ButtonGesture, budsLinked: Bool) -> UInt8 {
        budsLinked ? linkedNibble(gesture) : soloNibble(gesture)
    }

    /// The action that applies right now, `nil` if the gesture is disabled or unknown.
    public func currentAction(_ gesture: ButtonGesture, budsLinked: Bool) -> ButtonAction? {
        ButtonAction(rawValue: currentNibble(gesture, budsLinked: budsLinked))
    }

    /// The full byte to send when changing only the current nibble, like OpenSCQ30: the other
    /// nibble is kept as the earbuds reported it. `nil` action = disabled (0xF).
    public func byte(setting action: ButtonAction?, for gesture: ButtonGesture, budsLinked: Bool) -> UInt8 {
        let nibble = action?.rawValue ?? ButtonAction.disabledNibble
        let current = raw[gesture.rawValue]
        return budsLinked ? (current & 0xF0) | nibble : (nibble << 4) | (current & 0x0F)
    }
}
