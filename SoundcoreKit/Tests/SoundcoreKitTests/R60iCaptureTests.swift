import Testing
@testable import SoundcoreKit

/// Parsing and encoding against bytes captured from the real R60i NC.
@Suite("Real R60i NC capture")
struct R60iCaptureTests {
    let state: D1202State

    init() throws {
        var decoder = FrameDecoder()
        let events = decoder.feed(Fixtures.r60iStateFrame)
        let frames = events.compactMap { event -> Frame? in
            if case let .frame(frame) = event { frame } else { nil }
        }
        #expect(events.count == 1 && frames.first?.command == .state, "capture should decode as one 01 01 frame")
        state = try D1202State(body: try #require(frames.first).body)
    }

    @Test func header() {
        #expect(state.body.count == 152)
        #expect(state.firmwareLeft.displayString == "03.89")
        #expect(state.firmwareRight.displayString == "03.89")
        #expect(state.serialNumber == "12023409C9F6145A")
    }

    @Test func battery() {
        #expect(state.tws == TWSStatus(hostDeviceRaw: 1, isConnected: false))
        #expect(state.leftBattery.level.percent == nil) // 0xFF: left bud in the case
        #expect(state.rightBattery.level.percent == 100)
        #expect(state.caseBattery.percent == 80)
    }

    @Test func soundModes() {
        let modes = state.soundModes
        #expect(modes.raw == [0x02, 0x55, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01])
        #expect(modes.ambient == .normal)
        #expect(modes.manualLevelRaw == 5)
        #expect(modes.adaptiveStrengthRaw == 5)
        #expect(modes.adaptiveStrength == nil) // outside OpenSCQ30's Weak/Moderate/Strong
        #expect(modes.noiseCancelingMode == .adaptive)
        #expect(modes.windNoiseSuppression)
        #expect(modes.realTimeAdaptive)
    }

    @Test func settings() {
        #expect(state.equalizer.presetName == "Soundcore Signature")
        #expect(state.buttons.linkedNibble(.leftDouble) == ButtonAction.nextTrack.rawValue)
        #expect(state.touchTone)
        #expect(state.dualConnections)
        #expect(!state.ldac)
        #expect(state.autoPowerOff.minutes == 30)
        #expect(!state.volumeLimit.isEnabled)
    }

    /// Mode switches change byte 0 only. The read-only adaptive nibble (5) is sent back as read.
    @Test(arguments: [AmbientSoundMode.noiseCanceling, .transparency, .normal])
    func setModeChangesOnlyByteZero(mode: AmbientSoundMode) throws {
        var modes = state.soundModes
        modes.ambient = mode
        let body = try modes.encodedForWrite()
        #expect(body == [mode.rawValue, 0x55, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01])
    }

    @Test func transparencyFrame() throws {
        var modes = state.soundModes
        modes.ambient = .transparency
        let frame = try Requests.setSoundModes(modes).encoded()
        #expect(frame == [
            0x08, 0xEE, 0x00, 0x00, 0x00, 0x06, 0x81, 0x12, 0x00,
            0x01, 0x55, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
            0xE8,
        ])
    }
}
