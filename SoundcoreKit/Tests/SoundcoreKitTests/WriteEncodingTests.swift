import Testing
@testable import SoundcoreKit

/// Every write body against OpenSCQ30's test vectors (where one exists) or its encoder
/// (docs/protocol.md §7.2–7.4).
@Suite("Write encoders (protocol.md §7)")
struct WriteEncodingTests {
    /// The OpenSCQ30 D1202 fixture with spatial audio enabled (body bytes 137–138 = 01 03), as
    /// used by its `set_preset_eq` and `disable_spatial_audio` tests.
    static var spatialOnFixture: D1202State {
        var body = Fixtures.openSCQ30D1202StateBody
        body[137] = 1
        body[138] = 3
        return try! D1202State(body: body)
    }

    /// OpenSCQ30 `sc/d1202.rs` test `set_preset_eq`: select "Acoustic".
    @Test func presetEqualizerMatchesOpenSCQ30() {
        let state = Self.spatialOnFixture
        let acoustic = EqualizerPreset.all.first { $0.name == "Acoustic" }!
        let frame = Requests.setEqualizer(.preset(acoustic, hearID: state.hearID))
        #expect(frame.command == Command(0x03, 0x87))
        #expect(frame.body == [
            1, 0, 0, 0, 160, 130, 140, 140, 160, 160, 160, 140, 120, 0, 160, 130, 140,
            140, 160, 160, 160, 140, 120, 0, 0, 0, 0, 120, 120, 120, 120, 120, 120,
            120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 0, 0,
            0, 0, 2, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120,
            120, 120, 120, 120, 120, 120, 120, 160, 0, 130, 0, 140, 0, 140, 0, 160, 0,
            160, 0, 160, 0, 140, 0, 120, 0, 0, 0, 160, 0, 130, 0, 140, 0, 140, 0, 160,
            0, 160, 0, 160, 0, 140, 0, 120, 0, 0, 0, 0, 0,
        ])
        #expect(frame.body.count == 114)
    }

    /// OpenSCQ30 `sc/d1202.rs` test `disable_spatial_audio`.
    @Test func spatialAudioOffMatchesOpenSCQ30() {
        let state = Self.spatialOnFixture
        let frame = Requests.setEqualizer(.spatialAudioOff(current: state.equalizer, hearID: state.hearID))
        #expect(frame.body == [
            0, 0, 0, 0, 120, 120, 120, 120, 120, 120, 120, 120, 120, 0, 120, 120, 120,
            120, 120, 120, 120, 120, 120, 0, 0, 0, 0, 120, 120, 120, 120, 120, 120,
            120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 0, 0,
            0, 0, 2, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120,
            120, 120, 120, 120, 120, 120, 120, 120, 0, 120, 0, 120, 0, 120, 0, 120, 0,
            120, 0, 120, 0, 120, 0, 120, 0, 0, 0, 120, 0, 120, 0, 120, 0, 120, 0, 120,
            0, 120, 0, 120, 0, 120, 0, 120, 0, 0, 0, 0, 0,
        ])
    }

    /// OpenSCQ30 `sc/d1202.rs` test `enable_spatial_audio`: `10 81 [1, 0, 0]`.
    @Test func enableSpatialAudioMatchesOpenSCQ30() {
        let frame = Requests.enableSpatialAudio(mode: .music)
        #expect(frame.command == Command(0x10, 0x81))
        #expect(frame.body == [1, 0, 0])
        #expect(Requests.enableSpatialAudio(mode: .gaming).body == [1, 0, 3])
    }

    /// On the real R60i NC the HearID block is all FF (never run). The type byte is echoed (FF)
    /// rather than rewritten to 0 like OpenSCQ30; the other HearID bytes match OpenSCQ30.
    @Test func realCaptureEchoesHearIDBytes() throws {
        let state = try D1202State(body: Array(Fixtures.r60iStateFrame[9..<(Fixtures.r60iStateFrame.count - 1)]))
        let signature = EqualizerPreset.all[0]
        let body = Requests.setEqualizer(.preset(signature, hearID: state.hearID)).body
        #expect(body.count == 114)
        #expect(Array(body[0..<4]) == [0, 0, 0, 0]) // preset 0, genre 00 00 (state bytes 107–108)
        #expect(Array(body[4..<14]) == [120, 120, 120, 120, 120, 120, 120, 120, 120, 0])
        #expect(body[26] == 0) // HearID off
        #expect(Array(body[27..<47]) == Array(repeating: 0xFF, count: 20))
        #expect(Array(body[47..<51]) == [0xFF, 0, 0, 0]) // timestamp, echoed
        #expect(body[51] == 0xFF) // type byte, echoed
        #expect(Array(body[52..<72]) == Array(repeating: 0xFF, count: 20))
        #expect(Array(body[72..<92]) == [120, 0, 120, 0, 120, 0, 120, 0, 120, 0, 120, 0, 120, 0, 120, 0, 120, 0, 0, 0])
    }

    @Test func customEqualizer() {
        let state = Self.spatialOnFixture
        let write = EqualizerWrite.custom([10, -20, 0, 35, 0, 0, -120, 120], hearID: state.hearID)
        #expect(write.presetID == 0xFEFE)
        #expect(write.left == [130, 100, 120, 155, 120, 120, 0, 240, 120, 120])
        #expect(write.right == write.left)
        let body = Requests.setEqualizer(write).body
        #expect(Array(body[0..<2]) == [0xFE, 0xFE])
        #expect(Array(body[72..<92]) == [130, 0, 100, 0, 120, 0, 155, 0, 120, 0, 120, 0, 0, 0, 240, 0, 120, 0, 120, 0])
    }

    @Test func bandByteClamping() {
        #expect(EqualizerConfiguration.byte(forTenths: 0) == 120)
        #expect(EqualizerConfiguration.byte(forTenths: -120) == 0)
        #expect(EqualizerConfiguration.byte(forTenths: -500) == 0)
        #expect(EqualizerConfiguration.byte(forTenths: 134) == 254)
        #expect(EqualizerConfiguration.byte(forTenths: 500) == 254)
    }

    /// OpenSCQ30 `sc/a3330.rs` test vector `04 81 [1, 0, 0x63]` (same encoder for D1202).
    @Test func buttonAction() {
        let frame = Requests.setButtonAction(.rightDouble, actionByte: 0x63)
        #expect(frame.command == Command(0x04, 0x81))
        #expect(frame.body == [1, 0, 0x63])
        #expect(Requests.setButtonAction(.leftSingle, actionByte: 0xFF).body == [0, 2, 0xFF])
        #expect(Requests.setButtonAction(.leftTriple, actionByte: 0x66).body == [0, 5, 0x66])
        #expect(Requests.setButtonAction(.rightLong, actionByte: 0x44).body == [1, 1, 0x44])
        #expect(Requests.resetButtons().encoded() == [0x08, 0xEE, 0x00, 0x00, 0x00, 0x04, 0x82, 0x0A, 0x00, 0x86])
    }

    /// OpenSCQ30 edits only the nibble for the current TWS state and keeps the other one.
    @Test func buttonNibbleEditing() {
        let buttons = ButtonConfiguration(raw: [0xFF, 0xFF, 0x63, 0x66, 0xFF, 0xFF, 0x44, 0x44])
        #expect(buttons.byte(setting: .playPause, for: .leftDouble, budsLinked: true) == 0x66)
        #expect(buttons.byte(setting: .volumeUp, for: .leftDouble, budsLinked: false) == 0x03)
        #expect(buttons.byte(setting: nil, for: .rightLong, budsLinked: true) == 0x4F)
        #expect(buttons.byte(setting: .nextTrack, for: .leftSingle, budsLinked: true) == 0xF3)
        #expect(buttons.currentAction(.leftDouble, budsLinked: true) == .nextTrack)
        #expect(buttons.currentAction(.leftDouble, budsLinked: false) == .playPause)
        #expect(buttons.currentAction(.leftSingle, budsLinked: true) == nil)
    }

    @Test func gestureMapping() {
        for gesture in ButtonGesture.allCases {
            #expect(ButtonGesture(side: gesture.side, kind: gesture.kind) == gesture)
        }
        #expect(ButtonGesture.rightTriple.side == .right)
        #expect(ButtonGesture.rightTriple.kind == .triple)
        #expect(!GestureKind.single.allowedActions.contains(.ambientSoundMode))
        #expect(!GestureKind.single.allowedActions.contains(.voiceAssistant))
    }

    @Test func smallWrites() throws {
        #expect(Requests.setTouchTone(true).encoded() == [0x08, 0xEE, 0x00, 0x00, 0x00, 0x01, 0x83, 0x0B, 0x00, 0x01, 0x86])
        #expect(Requests.setLowBatteryPrompt(false).body == [0])
        #expect(Requests.setLowBatteryPrompt(false).command == Command(0x10, 0x82))
        #expect(Requests.setLDAC(true).command == Command(0x01, 0xFF))
        #expect(Requests.setAutoPowerOff(enabled: true, duration: .thirtyMinutes).body == [1, 2])
        #expect(Requests.setAutoPowerOff(enabled: false, duration: .sixtyMinutes).body == [0, 3])
        #expect(try Requests.setVolumeLimit(enabled: true, decibels: 85).body == [1, 85])
        #expect(throws: EncodeError.self) { try Requests.setVolumeLimit(enabled: true, decibels: 87) }
        #expect(throws: EncodeError.self) { try Requests.setVolumeLimit(enabled: true, decibels: 105) }
        #expect(Requests.setVolumeLimitRefreshRate(.oneMinute).body == [2])
        #expect(Requests.setDualConnections(true).body == [1])
        let mac = MACAddress([0x14, 0x92, 0x2C, 0x3A, 0xD4, 0x50])
        #expect(Requests.connectDualConnectionDevice(mac).body == [0x14, 0x92, 0x2C, 0x3A, 0xD4, 0x50])
        #expect(Requests.disconnectDualConnectionDevice(mac).command == Command(0x0B, 0x81))
        #expect(Requests.forgetDualConnectionDevice(mac).command == Command(0x0B, 0x83))
        #expect(Requests.fireAndForget == [Command(0x0B, 0x82), Command(0x0B, 0x81)])
    }
}

@Suite("Dual connections (protocol.md §6.8)")
struct DualConnectionTests {
    /// OpenSCQ30 `dual_connections_device.rs` test `round_trip`.
    @Test func parsesOpenSCQ30Vector() throws {
        let body: [UInt8] = [
            0x6, 0x1, 0x28, 0x1, 0x66, 0x14, 0x92, 0x2c, 0x3a, 0xd4, 0x50, 0x69, 0x78, 0x65, 0x6c,
            0x20, 0x36, 0x61, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
            0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
        ]
        let packet = try DualConnectionPacket(body: body)
        #expect(packet.total == 6)
        #expect(packet.index == 1)
        #expect(!packet.isLast)
        #expect(packet.devices == [DualConnectionDevice(
            isConnected: true,
            address: MACAddress([0x66, 0x14, 0x92, 0x2C, 0x3A, 0xD4]),
            name: "Pixel 6a"
        )])
        #expect(packet.devices[0].address.description == "66:14:92:2C:3A:D4")
    }

    /// OpenSCQ30 test `no_string_null_termination`.
    @Test func nameWithoutTerminator() throws {
        let body: [UInt8] = [
            0x6, 0x1, 0x28, 0x1, 0x66, 0x14, 0x92, 0x2c, 0x3a, 0xd4, 0x50, 0x69, 0x78, 0x65, 0x6c,
            0x20, 0x36, 0x61, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65, 65,
            65, 65, 65, 65, 65, 65, 65,
        ]
        let packet = try DualConnectionPacket(body: body)
        #expect(packet.devices.count == 1)
        #expect(packet.devices[0].name == "Pixel 6aAAAAAAAAAAAAAAAAAAAAAAAA")
    }

    /// A last record shorter than its length byte is truncated, not rejected (OpenSCQ30).
    @Test func shortLastRecord() throws {
        let body: [UInt8] = [1, 1, 0x28, 0, 1, 2, 3, 4, 5, 6, 0x4D, 0x61, 0x63]
        let packet = try DualConnectionPacket(body: body)
        #expect(packet.isLast)
        #expect(packet.devices.first?.name == "Mac")
        #expect(packet.devices.first?.isConnected == false)
    }
}

@Suite("Pushes (protocol.md §6.3–6.9)")
struct PushTests {
    @Test func pushesUpdateState() throws {
        var state = try D1202State(body: Fixtures.openSCQ30D1202StateBody)
        let applied1 = state.apply(push: Frame(.deviceToHost, .soundModes, body: [1, 0x30, 1, 0, 1, 0, 0, 0]))
        #expect(applied1)
        #expect(state.soundModes.ambient == .transparency)
        #expect(state.soundModes.transparency == .vocalMode)

        let applied2 = state.apply(push: Frame(.deviceToHost, .batteryLevel, body: [4, 0xFF, 0, 0]))
        #expect(applied2)
        #expect(state.leftBattery.level.percent == 50)
        #expect(state.rightBattery.level.percent == nil)

        let applied3 = state.apply(push: Frame(.deviceToHost, .batteryCharging, body: [1, 0]))
        #expect(applied3)
        #expect(state.leftBattery.isCharging)

        let applied4 = state.apply(push: Frame(.deviceToHost, .twsStatus, body: [0, 0]))
        #expect(applied4)
        #expect(!state.tws.isConnected)
        let applied5 = state.apply(push: Frame(.deviceToHost, .twsStatus, body: [0, 0, 0]))
        #expect(!applied5) // extra bytes rejected

        let applied6 = state.apply(push: Frame(.deviceToHost, .ldacState, body: [1]))
        #expect(applied6)
        #expect(state.ldac)

        let applied7 = state.apply(push: Frame(.deviceToHost, Command(0x01, 0x11), body: [1]))
        #expect(!applied7)
    }
}
