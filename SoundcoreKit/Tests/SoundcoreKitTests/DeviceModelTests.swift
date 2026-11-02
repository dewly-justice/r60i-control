import Testing
@testable import SoundcoreKit

/// An in-memory link that answers like the earbuds: `01 01` with a state body, and every write
/// with an empty-body ACK (docs/protocol.md §3). Replies arrive asynchronously, like RFCOMM.
@MainActor
final class FakeLink: PacketLink {
    var isOpen = true
    var onReceive: (([UInt8]) -> Void)?
    var onClose: (() -> Void)?
    var stateBody: [UInt8]
    /// Commands the fake never answers (to test timeouts).
    var silent: Set<Command> = []
    private(set) var written: [Frame] = []

    init(stateBody: [UInt8]) {
        self.stateBody = stateBody
    }

    func write(_ bytes: [UInt8]) throws(SoundcoreError) {
        var decoder = FrameDecoder(expecting: .hostToDevice)
        guard case let .frame(frame)? = decoder.feed(bytes).first else { return }
        written.append(frame)
        guard !silent.contains(frame.command), !Requests.fireAndForget.contains(frame.command) else { return }
        let reply = switch frame.command {
        case .state: Frame(.deviceToHost, .state, body: stateBody)
        case .dualConnectionDevices: Frame(.deviceToHost, .dualConnectionDevices, body: Self.deviceList)
        default: Frame(.deviceToHost, frame.command)
        }
        Task { @MainActor [weak self] in self?.onReceive?(reply.encoded()) }
    }

    func push(_ frame: Frame) {
        onReceive?(frame.encoded())
    }

    func close() async {
        isOpen = false
    }

    /// Everything except the two reads (`01 01`, `0B 01`).
    var writes: [Frame] { written.filter { $0.command != .state && $0.command != .dualConnectionDevices } }

    /// One `0B 01` packet with two devices (record layout from docs/protocol.md §6.8).
    static let deviceList: [UInt8] = {
        func record(_ connected: Bool, _ mac: [UInt8], _ name: String) -> [UInt8] {
            let nameBytes = Array(name.utf8) + Array(repeating: 0, count: 32 - name.utf8.count)
            return [UInt8(8 + nameBytes.count), connected ? 1 : 0] + mac + nameBytes
        }
        return [1, 1] + record(true, [1, 2, 3, 4, 5, 6], "Phone") + record(false, [6, 5, 4, 3, 2, 1], "Laptop")
    }()
}

@Suite("Device model over a fake link")
@MainActor
struct DeviceModelTests {
    static let summary = ConnectionSummary(
        displayName: "fake R60i NC", channelID: 15, serviceUUID: SoundcoreServiceUUID.d1202c,
        vendorSuffix: "1202C", fromCache: true
    )
    static var r60iBody: [UInt8] { Array(Fixtures.r60iStateFrame[9..<(Fixtures.r60iStateFrame.count - 1)]) }

    func connected(body: [UInt8] = r60iBody, summary: ConnectionSummary = summary) async throws -> (SoundcoreDevice, FakeLink) {
        let link = FakeLink(stateBody: body)
        let device = SoundcoreDevice()
        try await device.attach(link: link, connection: summary)
        return (device, link)
    }

    @Test func connectReadsState() async throws {
        let (device, link) = try await connected()
        #expect(device.status == .connected)
        #expect(device.isConnected)
        #expect(device.state?.firmwareRight.displayString == "03.89")
        // Dual connection is on in the capture, so the device list is read too (§4).
        #expect(link.written.map(\.command) == [.state, .dualConnectionDevices])
        #expect(device.dualConnectionDevices.map(\.name) == ["Phone", "Laptop"])
        #expect(device.dualConnectionDevices.first?.isConnected == true)
    }

    @Test func setModeSendsOnlyByteZeroChange() async throws {
        let (device, link) = try await connected()
        try await device.setAmbientMode(.transparency)
        #expect(link.writes.map { $0.encoded() } == [[
            0x08, 0xEE, 0x00, 0x00, 0x00, 0x06, 0x81, 0x12, 0x00,
            0x01, 0x55, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0xE8,
        ]])
        #expect(device.state?.soundModes.ambient == .transparency)
        // Already in that mode: nothing more is sent.
        try await device.setAmbientMode(.transparency)
        #expect(link.writes.count == 1)
    }

    @Test func cycleOrder() async throws {
        let (device, _) = try await connected() // Normal
        try await device.cycleAmbientMode()
        #expect(device.state?.soundModes.ambient == .noiseCanceling)
        try await device.cycleAmbientMode()
        #expect(device.state?.soundModes.ambient == .transparency)
        try await device.cycleAmbientMode()
        #expect(device.state?.soundModes.ambient == .normal)
    }

    @Test func soundModeFieldsKeepTheRest() async throws {
        let (device, link) = try await connected()
        try await device.setManualNoiseCancelingLevel(2)
        try await device.setNoiseCancelingMode(.manual)
        try await device.setWindNoiseSuppression(false)
        let bodies = link.writes.map(\.body)
        #expect(bodies == [
            [0x02, 0x25, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01],
            [0x02, 0x25, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01],
            [0x02, 0x25, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01],
        ])
    }

    /// The real capture has only the right bud out (TWS not linked), so button edits change the
    /// solo (high) nibble, as in OpenSCQ30.
    @Test func buttonWriteUsesCurrentTWSNibble() async throws {
        let (device, link) = try await connected()
        try await device.setButtonAction(.volumeUp, side: .right, kind: .double)
        #expect(link.writes.last?.body == [1, 0, 0x06]) // was 0x66: solo nibble 6 → 0
        #expect(device.state?.buttons.currentAction(.rightDouble, budsLinked: false) == .volumeUp)
        await #expect(throws: SoundcoreError.self) {
            try await device.setButtonAction(.voiceAssistant, side: .left, kind: .single)
        }
    }

    /// The capture with both buds linked (state byte 1 = TWS connected).
    static var linkedBody: [UInt8] {
        var body = r60iBody
        body[1] = 1
        return body
    }

    @Test func equalizerWriteRereadsState() async throws {
        let (device, link) = try await connected(body: Self.linkedBody)
        try await device.selectEqualizerPreset(EqualizerPreset.all[2])
        #expect(link.written.map(\.command) == [.state, .dualConnectionDevices, .setEqualizer, .state])
        #expect(link.writes.first?.body.count == 114)
    }

    /// Like OpenSCQ30, the EQ isn't changed while only one bud is linked.
    @Test func equalizerNeedsBothEarbuds() async throws {
        let (device, link) = try await connected() // capture: right bud only
        await #expect(throws: SoundcoreError.bothEarbudsRequired) {
            try await device.selectEqualizerPreset(EqualizerPreset.all[2])
        }
        await #expect(throws: SoundcoreError.bothEarbudsRequired) {
            try await device.setCustomEqualizer([0, 0, 0, 0, 0, 0, 0, 0])
        }
        #expect(link.writes.isEmpty)
    }

    @Test func spatialAudioOffIsAnEqualizerPacket() async throws {
        let (device, link) = try await connected() // spatial on, Music
        try await device.setSpatialAudio(enabled: false, mode: .music)
        #expect(link.writes.map(\.command) == [.setEqualizer])
        try await device.setSpatialAudio(enabled: true, mode: .movie)
        #expect(link.writes.last?.body == [1, 0, 2])
    }

    @Test func unacknowledgedWriteRollsBack() async throws {
        let (device, link) = try await connected()
        link.silent = [.setTouchTone]
        await #expect(throws: SoundcoreError.timeout(.setTouchTone)) {
            try await device.setTouchTone(false)
        }
        #expect(device.state?.touchTone == true)
        #expect(link.writes.count == 3) // first try + 2 retries
    }

    @Test func pushUpdatesState() async throws {
        let (device, link) = try await connected()
        link.push(Frame(.deviceToHost, .soundModes, body: [0, 0x55, 0, 1, 1, 0, 0, 1]))
        #expect(device.state?.soundModes.ambient == .noiseCanceling)
        link.push(Frame(.deviceToHost, .batteryLevel, body: [5, 8]))
        #expect(device.state?.leftBattery.level.percent == 60)
        #expect(device.state?.rightBattery.level.percent == 90)
    }

    @Test func refusesWritesForUnconfirmedModel() async throws {
        let other = ConnectionSummary(
            displayName: "other", channelID: 15, serviceUUID: SoundcoreServiceUUID.d1202c,
            vendorSuffix: "3951A", fromCache: true
        )
        let (device, link) = try await connected(summary: other)
        await #expect(throws: SoundcoreError.self) { try await device.setAmbientMode(.noiseCanceling) }
        #expect(link.writes.isEmpty)
    }

    @Test func closedLinkDisconnects() async throws {
        let (device, link) = try await connected()
        link.isOpen = false
        link.onClose?()
        #expect(device.state == nil)
        #expect(!device.isConnected)
        await #expect(throws: SoundcoreError.notConnected) { try await device.setLDAC(true) }
    }
}
