import Testing
@testable import SoundcoreKit

@Suite("D1202 state packet (protocol.md §6.1)")
struct StateTests {
    let state: D1202State

    init() throws {
        state = try D1202State(body: Fixtures.openSCQ30D1202StateBody)
    }

    // Expected values are the ones OpenSCQ30's `settings_match_soundcore_app` test asserts.

    @Test func status() {
        #expect(state.tws == TWSStatus(hostDeviceRaw: 1, isConnected: true))
        #expect(state.leftBattery == EarbudBattery(level: BatteryLevel(raw: 9), isCharging: false))
        #expect(state.rightBattery.level.percent == 100)
        #expect(state.caseBattery.percent == 40) // "4/10"
        #expect(state.firmwareLeft.displayString == "01.83")
        #expect(state.firmwareRight.displayString == "01.83")
        #expect(state.serialNumber == "12023409C9B403CE")
    }

    @Test func soundModes() {
        let modes = state.soundModes
        #expect(modes.ambient == .noiseCanceling)
        #expect(modes.manualLevelRaw == 5)
        #expect(modes.adaptiveStrength == .weak)
        #expect(modes.noiseCancelingMode == .multiScene)
        #expect(modes.multiScene == .transport)
        #expect(modes.transparency == .fullyTransparent)
        #expect(!modes.windNoiseSuppression)
        #expect(!modes.realTimeAdaptive)
    }

    @Test func equalizer() {
        #expect(state.equalizer.presetID == 0)
        #expect(state.equalizer.presetName == "Soundcore Signature")
        #expect(state.equalizer.left == Array(repeating: 0, count: 10))
        #expect(state.equalizer.right == nil) // channel starts with 0xFF
    }

    @Test func buttons() {
        #expect(state.buttons.linkedNibble(.leftSingle) == ButtonAction.disabledNibble)
        #expect(state.buttons.linkedNibble(.leftDouble) == ButtonAction.nextTrack.rawValue)
        #expect(state.buttons.linkedNibble(.rightDouble) == ButtonAction.playPause.rawValue)
        #expect(state.buttons.linkedNibble(.leftTriple) == ButtonAction.disabledNibble)
        #expect(state.buttons.linkedNibble(.leftLong) == ButtonAction.ambientSoundMode.rawValue)
        #expect(state.buttons.linkedNibble(.rightLong) == ButtonAction.ambientSoundMode.rawValue)
    }

    @Test func otherSettings() {
        #expect(state.touchTone)
        #expect(state.lowBatteryPrompt)
        #expect(!state.ldac)
        #expect(state.dualConnections)
        #expect(state.autoPowerOff == AutoPowerOff(isEnabled: true, durationIndex: 2))
        #expect(state.autoPowerOff.minutes == 30)
        #expect(state.volumeLimit == VolumeLimit(isEnabled: false, decibels: 90, refreshRateRaw: 0))
        #expect(state.spatialAudio.isEnabled == false)
        #expect(state.spatialAudio.mode == .music)
        #expect(state.body.count == 152)
    }

    @Test func tooShortBodyFails() {
        #expect(throws: ParseError.tooShort(what: "D1202 state", needed: 139, got: 138)) {
            try D1202State(body: Array(Fixtures.openSCQ30D1202StateBody.prefix(138)))
        }
    }

    @Test func minimumBodyParses() throws {
        let state = try D1202State(body: Array(Fixtures.openSCQ30D1202StateBody.prefix(139)))
        #expect(state.spatialAudio.mode == .music)
    }
}

@Suite("Set sound modes 06 81 (protocol.md §6.2, §7.2)")
struct SetSoundModesTests {
    @Test("Changing only the ambient mode produces the expected frame")
    func transparencyFrame() throws {
        var modes = try D1202State(body: Fixtures.openSCQ30D1202StateBody).soundModes
        modes.ambient = .transparency
        let frame = try Requests.setSoundModes(modes)
        #expect(frame.encoded() == [
            0x08, 0xEE, 0x00, 0x00, 0x00, 0x06, 0x81, 0x12, 0x00,
            0x01, 0x50, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00,
            0xE2,
        ])
    }

    @Test("Each mode only changes byte 0")
    func onlyByteZeroChanges() throws {
        let original = try D1202State(body: Fixtures.openSCQ30D1202StateBody).soundModes
        for mode in AmbientSoundMode.allCases {
            var modes = original
            modes.ambient = mode
            let body = try modes.encodedForWrite()
            #expect(body[0] == mode.rawValue)
            #expect(Array(body.dropFirst()) == Array(original.raw.dropFirst()))
        }
    }

    @Test("Normalization matches OpenSCQ30: byte 5 → 0, manual level clamped, wind bit 1 kept")
    func normalization() throws {
        let modes = try SoundModes(bytes: [2, 0x02, 1, 1, 0x03, 0x7A, 2, 1])
        #expect(try modes.encodedForWrite() == [2, 0x12, 1, 1, 0x03, 0, 2, 1])
    }

    @Test("Unknown enum values are refused instead of being rewritten")
    func refusesUnknown() throws {
        let unknownAmbient = try SoundModes(bytes: [7, 0x50, 0, 0, 0, 0, 0, 0])
        #expect(throws: EncodeError.self) { try unknownAmbient.encodedForWrite() }

        let unknownScene = try SoundModes(bytes: [0, 0x50, 0, 2, 0, 0, 9, 0])
        #expect(throws: EncodeError.self) { try unknownScene.encodedForWrite() }

        let oddWindBits = try SoundModes(bytes: [0, 0x50, 0, 0, 0x04, 0, 0, 0])
        #expect(throws: EncodeError.self) { try oddWindBits.encodedForWrite() }
    }
}
