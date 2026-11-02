// Every host → device frame the code can build. Each one is cited in docs/protocol.md §7,
// and every body layout here was checked against OpenSCQ30's encoder (and its test vector,
// where one exists). Rule: a command not listed here is never sent.

public enum Requests {
    // MARK: Reads (§7.1)

    /// `01 01`, empty body. The reply is the full state packet (§6.1).
    public static func requestState() -> Frame {
        Frame(.hostToDevice, .state)
    }

    /// `0B 01`, empty body. The reply is one or more `0B 01` frames (§6.8).
    public static func requestDualConnectionDevices() -> Frame {
        Frame(.hostToDevice, .dualConnectionDevices)
    }

    // MARK: Writes (§7.2)

    /// `06 81` with the 8-byte sound-modes block (§6.2).
    public static func setSoundModes(_ modes: SoundModes) throws(EncodeError) -> Frame {
        Frame(.hostToDevice, .setSoundModes, body: try modes.encodedForWrite())
    }

    /// `03 87` with the 114-byte D1202 equalizer body (§7.3).
    public static func setEqualizer(_ write: EqualizerWrite) -> Frame {
        Frame(.hostToDevice, .setEqualizer, body: write.body)
    }

    /// `10 81 [01, 00, mode]`. Only ever sent with "enabled": spatial audio is turned off with
    /// an `03 87` packet instead, like the Soundcore app (§7.4).
    public static func enableSpatialAudio(mode: SpatialAudioMode) -> Frame {
        Frame(.hostToDevice, .setSpatialAudio, body: [1, 0, mode.rawValue])
    }

    /// `04 81 [side, button_id, action_byte]` (§8.7). The action byte holds both nibbles.
    public static func setButtonAction(_ gesture: ButtonGesture, actionByte: UInt8) -> Frame {
        Frame(.hostToDevice, .setButtonAction, body: [gesture.side.rawValue, gesture.kind.buttonID, actionByte])
    }

    /// `04 82`, empty body. Afterwards, request the state again (§7.2).
    public static func resetButtons() -> Frame {
        Frame(.hostToDevice, .resetButtons)
    }

    /// `20 82 [enabled, dB]`, dB 75…100 in steps of 5.
    public static func setVolumeLimit(enabled: Bool, decibels: UInt8) throws(EncodeError) -> Frame {
        guard VolumeLimit.decibelRange.contains(decibels), decibels % 5 == 0 else {
            throw .outOfRange("volume limit \(decibels) dB (allowed: 75…100 in steps of 5)")
        }
        return Frame(.hostToDevice, .setVolumeLimit, body: [enabled ? 1 : 0, decibels])
    }

    /// `20 81 [rate]` (§8.9).
    public static func setVolumeLimitRefreshRate(_ rate: DecibelRefreshRate) -> Frame {
        Frame(.hostToDevice, .setVolumeLimitRefreshRate, body: [rate.rawValue])
    }

    /// `0B 84 [bool]`.
    public static func setDualConnections(_ enabled: Bool) -> Frame {
        Frame(.hostToDevice, .setDualConnections, body: [enabled ? 1 : 0])
    }

    /// `0B 83 [MAC]`. Removes the pairing from the earbuds. Waits for an ACK.
    public static func forgetDualConnectionDevice(_ address: MACAddress) -> Frame {
        Frame(.hostToDevice, .forgetDualConnectionDevice, body: address.bytes)
    }

    /// `0B 82 [MAC]`. Fire-and-forget: OpenSCQ30 doesn't wait for an ACK.
    public static func connectDualConnectionDevice(_ address: MACAddress) -> Frame {
        Frame(.hostToDevice, .connectDualConnectionDevice, body: address.bytes)
    }

    /// `0B 81 [MAC]`. Fire-and-forget: OpenSCQ30 doesn't wait for an ACK.
    public static func disconnectDualConnectionDevice(_ address: MACAddress) -> Frame {
        Frame(.hostToDevice, .disconnectDualConnectionDevice, body: address.bytes)
    }

    /// `01 86 [enabled, duration_index]` (§8.8).
    public static func setAutoPowerOff(enabled: Bool, duration: AutoPowerOffDuration) -> Frame {
        Frame(.hostToDevice, .setAutoPowerOff, body: [enabled ? 1 : 0, duration.rawValue])
    }

    /// `01 83 [bool]`.
    public static func setTouchTone(_ enabled: Bool) -> Frame {
        Frame(.hostToDevice, .setTouchTone, body: [enabled ? 1 : 0])
    }

    /// `10 82 [bool]`.
    public static func setLowBatteryPrompt(_ enabled: Bool) -> Frame {
        Frame(.hostToDevice, .setLowBatteryPrompt, body: [enabled ? 1 : 0])
    }

    /// `01 FF [bool]`.
    public static func setLDAC(_ enabled: Bool) -> Frame {
        Frame(.hostToDevice, .setLDAC, body: [enabled ? 1 : 0])
    }

    /// Writes the device doesn't acknowledge (§7.2). Everything else waits for an ACK.
    public static let fireAndForget: Set<Command> = [.connectDualConnectionDevice, .disconnectDualConnectionDevice]
}
