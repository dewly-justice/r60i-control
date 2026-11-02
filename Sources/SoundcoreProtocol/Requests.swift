// Every host → device frame the code can build. Each one is cited in docs/protocol.md §7.
// Rule: a command not listed here is never sent.

public enum Requests {
    /// `01 01`, empty body. The reply is the full state packet (§6.1).
    public static func requestState() -> Frame {
        Frame(.hostToDevice, .state)
    }

    /// `06 81` with the 8-byte sound-modes block (§6.2, §7.2).
    public static func setSoundModes(_ modes: SoundModes) throws(EncodeError) -> Frame {
        Frame(.hostToDevice, .setSoundModes, body: try modes.encodedForWrite())
    }
}
