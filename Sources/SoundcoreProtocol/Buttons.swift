// Touch controls: docs/protocol.md §5 (action byte) and §8.7.
// Each gesture byte: low nibble = action while the buds are linked, high nibble = action when
// one bud is used alone. 0xF = disabled.

public enum ButtonGesture: Int, Sendable, CaseIterable {
    // Order matches the state packet (offset 0x6E).
    case leftSingle, rightSingle, leftDouble, rightDouble, leftTriple, rightTriple, leftLong, rightLong

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

public enum ButtonAction: UInt8, Sendable, CaseIterable {
    case volumeUp = 0
    case volumeDown = 1
    case previousTrack = 2
    case nextTrack = 3
    case ambientSoundMode = 4
    case voiceAssistant = 5
    case playPause = 6

    public static let disabledNibble: UInt8 = 0xF

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
}
