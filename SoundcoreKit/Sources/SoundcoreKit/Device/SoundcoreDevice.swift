import Foundation
import IOBluetooth
import Observation

/// Something worth logging: link traffic, pushes, and connection milestones.
public enum DeviceEvent: Sendable {
    case link(LinkEvent)
    case push(Frame)
    case info(String)
}

/// The earbuds, as the app sees them: connection status plus the last known device state.
///
/// Everything happens on the main actor. Reads come from the `01 01` state packet and from pushes;
/// every write is one of the packets in `Requests` (docs/protocol.md §7.2). Writes update `state`
/// optimistically, and roll back (then re-read the state) if the earbuds don't acknowledge.
@MainActor
@Observable
public final class SoundcoreDevice {
    public enum Status: Equatable, Sendable {
        /// Auto-connect not started, and no manual connection.
        case idle
        case bluetoothOff
        /// No paired device looks like an R60i NC.
        case notPaired
        /// Paired, but not connected to this Mac.
        case disconnected
        case connecting
        case connected
        /// Connected to this Mac, but the control channel failed. Auto-connect retries.
        case unavailable(String)
    }

    public private(set) var status: Status = .idle
    public private(set) var deviceName: String?
    public private(set) var deviceAddress: String?
    public private(set) var connection: ConnectionSummary?
    public private(set) var state: D1202State?
    public private(set) var dualConnectionDevices: [DualConnectionDevice] = []
    public private(set) var lastRefresh: Date?
    /// Writes in flight, for a progress indicator.
    public private(set) var pendingWrites = 0

    public var isConnected: Bool { status == .connected && state != nil }

    /// Link traffic and connection milestones (scprobe `--hexdump`, the app's debug log).
    @ObservationIgnored public var onEvent: ((DeviceEvent) -> Void)?
    /// Address to prefer when several paired devices match.
    @ObservationIgnored public var preferredAddress: String?

    @ObservationIgnored private var session: PacketSession?
    @ObservationIgnored private var device: IOBluetoothDevice?
    @ObservationIgnored private var watcher: ConnectionWatcher?
    @ObservationIgnored private var maintenanceTask: Task<Void, Never>?
    @ObservationIgnored private var connecting = false
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var nextAttempt = ContinuousClock.now
    @ObservationIgnored private var dualListBuffer: [DualConnectionDevice] = []

    /// How often auto-connect re-checks Bluetooth while not connected.
    @ObservationIgnored public var pollInterval: Duration = .seconds(4)
    /// While connected, re-read the full state this often (case battery has no push, §6.9).
    @ObservationIgnored public var refreshInterval: Duration = .seconds(300)

    public init() {}

    // MARK: - Auto-connect (the app)

    /// Watches for the earbuds and keeps a control connection open whenever they're connected
    /// to this Mac: connects on launch, when they connect, and again after the channel drops.
    public func startAutoConnect() {
        guard maintenanceTask == nil else { return }
        watcher = ConnectionWatcher(
            onConnect: { [weak self] device in self?.bluetoothDeviceConnected(device) },
            onDisconnect: { [weak self] device in self?.bluetoothDeviceDisconnected(device) }
        )
        watcher?.start()
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.maintain()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    public func stopAutoConnect() async {
        maintenanceTask?.cancel()
        maintenanceTask = nil
        watcher?.stop()
        watcher = nil
        await disconnect()
    }

    /// One pass of the auto-connect loop.
    private func maintain() async {
        if isConnected {
            if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) > refreshInterval.seconds {
                _ = try? await refreshState()
            }
            return
        }
        guard !connecting else { return }
        guard DeviceDiscovery.isBluetoothPoweredOn else {
            setStatus(.bluetoothOff)
            return
        }
        guard let candidate = preferredCandidate() else {
            setStatus(.notPaired)
            return
        }
        deviceName = candidate.name
        deviceAddress = candidate.addressString
        guard candidate.isConnected() else {
            setStatus(.disconnected)
            failures = 0
            return
        }
        guard ContinuousClock.now >= nextAttempt else { return }
        do {
            try await connect(to: candidate)
        } catch {
            failures += 1
            // 2, 4, 8, 16, 30, 30… seconds
            let delay = min(30, 1 << min(failures, 5))
            nextAttempt = .now + .seconds(delay)
            emit(.info("Connecting failed (\(error)); retrying in \(delay) s."))
        }
    }

    private func preferredCandidate() -> IOBluetoothDevice? {
        let candidates = DeviceDiscovery.candidates()
        if let preferredAddress, let match = candidates.first(where: { $0.addressString == preferredAddress }) {
            return match
        }
        return candidates.first
    }

    private func bluetoothDeviceConnected(_ device: IOBluetoothDevice) {
        guard maintenanceTask != nil, !isConnected, !connecting, DeviceDiscovery.isCandidate(device) else { return }
        emit(.info("\(DeviceDiscovery.label(device)) connected to this Mac."))
        // Give the earbuds a moment to finish connecting their audio profiles.
        failures = 0
        nextAttempt = .now + .milliseconds(1500)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
            await self?.maintain()
        }
    }

    private func bluetoothDeviceDisconnected(_ device: IOBluetoothDevice) {
        guard device.addressString == self.device?.addressString else { return }
        emit(.info("\(DeviceDiscovery.label(device)) disconnected from this Mac."))
        Task { [weak self] in
            await self?.disconnect()
            self?.setStatus(.disconnected)
        }
    }

    /// Asks macOS to connect the paired earbuds to this Mac (baseband connection). Auto-connect
    /// then opens the control channel.
    public func requestBluetoothConnection() {
        guard let watcher, let candidate = preferredCandidate(), !candidate.isConnected() else { return }
        let status = candidate.openConnection(watcher)
        emit(.info("Asked macOS to connect \(DeviceDiscovery.label(candidate)): \(ioReturnDescription(status))"))
    }

    // MARK: - Connecting (shared by the app and scprobe)

    /// Opens the control channel to `device` and reads its state.
    public func connect(to device: IOBluetoothDevice, forceSDPRefresh: Bool = false) async throws(SoundcoreError) {
        connecting = true
        defer { connecting = false }
        await closeSession()
        self.device = device
        deviceName = device.name
        deviceAddress = device.addressString
        setStatus(.connecting)

        do {
            let log: (String) -> Void = { [weak self] message in self?.emit(.info(message)) }
            var summary = try await DeviceDiscovery.resolveService(on: device, forceRefresh: forceSDPRefresh, log: log)
            emit(.info("Connecting to \(summary.displayName) on RFCOMM channel \(summary.channelID)…"))
            let link: RFCOMMLink
            do {
                link = try await RFCOMMLink.open(device: device, channelID: summary.channelID, log: log)
            } catch where summary.fromCache {
                // A cached SDP record may hold an old channel number. Refresh once and retry.
                emit(.info("Open failed (\(error)); refreshing SDP records and retrying once…"))
                summary = try await DeviceDiscovery.resolveService(on: device, forceRefresh: true, log: log)
                link = try await RFCOMMLink.open(device: device, channelID: summary.channelID, log: log)
            }
            emit(.info("Connected."))
            try await attach(link: link, connection: summary)
            watcher?.watchDisconnect(of: device)
        } catch {
            await closeSession()
            setStatus(.unavailable(error.description))
            throw error
        }
    }

    /// Starts a session on an open link and reads the state (§4). `connect(to:)` uses this; tests
    /// call it with a fake link.
    func attach(link: any PacketLink, connection summary: ConnectionSummary) async throws(SoundcoreError) {
        connection = summary
        let session = PacketSession(link: link)
        session.onEvent = { [weak self] event in self?.emit(.link(event)) }
        session.onPush = { [weak self] frame in self?.handlePush(frame) }
        session.onClose = { [weak self] in self?.sessionClosed() }
        self.session = session

        let fresh = try await session.readState()
        state = fresh
        lastRefresh = .now
        if fresh.dualConnections {
            dualConnectionDevices = (try? await session.readDualConnectionDevices()) ?? []
        }
        failures = 0
        setStatus(.connected)
    }

    /// Closes the control channel (the audio connection stays up).
    public func disconnect() async {
        await closeSession()
        if status == .connected || status == .connecting { setStatus(.idle) }
    }

    private func closeSession() async {
        guard let session else { return }
        self.session = nil
        session.onClose = nil
        await session.close()
        state = nil
        connection = nil
        dualConnectionDevices = []
    }

    private func sessionClosed() {
        emit(.info("The earbuds closed the control channel."))
        session = nil
        state = nil
        connection = nil
        dualConnectionDevices = []
        let stillConnected = device?.isConnected() ?? false
        setStatus(stillConnected ? .unavailable("The control channel closed.") : .disconnected)
        // Auto-connect reopens it on its next pass.
        nextAttempt = .now + .seconds(1)
    }

    private func setStatus(_ new: Status) {
        if status != new { status = new }
    }

    private func emit(_ event: DeviceEvent) {
        onEvent?(event)
    }

    // MARK: - Reading

    /// Re-reads the full state (`01 01`).
    @discardableResult
    public func refreshState() async throws(SoundcoreError) -> D1202State {
        guard let session else { throw .notConnected }
        let fresh = try await session.readState()
        state = fresh
        lastRefresh = .now
        return fresh
    }

    /// Re-reads the state if the last read is older than `age`.
    public func refreshIfStale(olderThan age: Duration = .seconds(15)) async {
        guard isConnected else { return }
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < age.seconds { return }
        _ = try? await refreshState()
    }

    /// Re-reads the dual-connection device list (`0B 01`).
    public func reloadDualConnectionDevices() async throws(SoundcoreError) {
        guard let session else { throw .notConnected }
        dualConnectionDevices = try await session.readDualConnectionDevices()
    }

    private func handlePush(_ frame: Frame) {
        emit(.push(frame))
        switch frame.command {
        case .state:
            if let fresh = try? D1202State(body: frame.body) {
                state = fresh
                lastRefresh = .now
            }
        case .dualConnectionDevices:
            guard let packet = try? DualConnectionPacket(body: frame.body) else { return }
            if packet.index <= 1 { dualListBuffer = [] }
            dualListBuffer += packet.devices
            if packet.isLast { dualConnectionDevices = dualListBuffer }
        default:
            state?.apply(push: frame)
        }
    }

    // MARK: - Writing

    /// Sends one write. `optimistic` updates the cached state right away; it is rolled back if
    /// the earbuds don't acknowledge. `refreshAfter` re-reads the state once the write is done,
    /// for writes with side effects (EQ turns spatial audio off, button reset, …).
    private func perform(
        _ frame: Frame,
        refreshAfter: Bool = false,
        optimistic: (inout D1202State) -> Void
    ) async throws(SoundcoreError) {
        guard let session, isConnected, var draft = state else { throw .notConnected }
        guard let connection, connection.modelConfirmed else {
            throw .unconfirmedModel(connection?.modelNote ?? "unknown model")
        }
        let previous = draft
        optimistic(&draft)
        state = draft
        pendingWrites += 1
        defer { pendingWrites -= 1 }
        do {
            if Requests.fireAndForget.contains(frame.command) {
                try await session.sendWithoutReply(frame)
            } else {
                _ = try await session.exchange(frame)
            }
        } catch {
            if state == draft { state = previous }
            if session.isOpen { _ = try? await refreshState() }
            throw error
        }
        if refreshAfter { _ = try? await refreshState() }
    }

    private func currentState() throws(SoundcoreError) -> D1202State {
        guard let state, isConnected else { throw .notConnected }
        return state
    }

    // MARK: Sound modes (06 81)

    public func setAmbientMode(_ mode: AmbientSoundMode) async throws(SoundcoreError) {
        try await updateSoundModes { $0.ambient = mode }
    }

    /// Noise Canceling → Transparency → Normal → Noise Canceling.
    public func cycleAmbientMode() async throws(SoundcoreError) {
        let order: [AmbientSoundMode] = [.noiseCanceling, .transparency, .normal]
        let current = try currentState().soundModes.ambient ?? .normal
        let next = order[((order.firstIndex(of: current) ?? 0) + 1) % order.count]
        try await setAmbientMode(next)
    }

    public func setNoiseCancelingMode(_ mode: NoiseCancelingMode) async throws(SoundcoreError) {
        try await updateSoundModes { $0.noiseCancelingMode = mode }
    }

    public func setManualNoiseCancelingLevel(_ level: Int) async throws(SoundcoreError) {
        try await updateSoundModes { $0.manualLevel = level }
    }

    public func setMultiScene(_ scene: MultiSceneMode) async throws(SoundcoreError) {
        try await updateSoundModes { $0.multiScene = scene }
    }

    public func setTransparencyMode(_ mode: TransparencyMode) async throws(SoundcoreError) {
        try await updateSoundModes { $0.transparency = mode }
    }

    public func setWindNoiseSuppression(_ enabled: Bool) async throws(SoundcoreError) {
        try await updateSoundModes { $0.windNoiseSuppression = enabled }
    }

    public func setRealTimeAdaptive(_ enabled: Bool) async throws(SoundcoreError) {
        try await updateSoundModes { $0.realTimeAdaptive = enabled }
    }

    private func updateSoundModes(_ change: (inout SoundModes) -> Void) async throws(SoundcoreError) {
        let current = try currentState().soundModes
        var modes = current
        change(&modes)
        guard modes != current else { return }
        let frame: Frame
        do {
            frame = try Requests.setSoundModes(modes)
        } catch {
            throw .encode(error)
        }
        let sent = (try? SoundModes(bytes: frame.body)) ?? modes
        try await perform(frame) { $0.soundModes = sent }
    }

    // MARK: Equalizer and spatial audio (03 87, 10 81)

    public func selectEqualizerPreset(_ preset: EqualizerPreset) async throws(SoundcoreError) {
        try await writeEqualizer(.preset(preset, hearID: try currentState().hearID))
    }

    /// Custom EQ: 8 bands in tenths of a dB.
    public func setCustomEqualizer(_ bands: [Int]) async throws(SoundcoreError) {
        guard bands.count == EqualizerConfiguration.visibleBandCount else {
            throw .encode(.outOfRange("\(bands.count) EQ bands (need \(EqualizerConfiguration.visibleBandCount))"))
        }
        try await writeEqualizer(.custom(bands, hearID: try currentState().hearID))
    }

    private func writeEqualizer(_ write: EqualizerWrite) async throws(SoundcoreError) {
        // The earbuds turn spatial audio off after an EQ write (§7.4).
        try await perform(Requests.setEqualizer(write), refreshAfter: true) { state in
            state.equalizer = write.resultingConfiguration
            state.spatialAudio.isEnabled = false
        }
    }

    /// Turns spatial audio on (with `mode`) or off. Off is an EQ packet, like the Soundcore app (§7.4).
    public func setSpatialAudio(enabled: Bool, mode: SpatialAudioMode) async throws(SoundcoreError) {
        let state = try currentState()
        let current = state.spatialAudio
        if enabled {
            guard !(current.isEnabled && current.mode == mode) else { return }
            try await perform(Requests.enableSpatialAudio(mode: mode), refreshAfter: true) {
                $0.spatialAudio = SpatialAudio(isEnabled: true, modeRaw: mode.rawValue)
            }
        } else {
            guard current.isEnabled else { return }
            if current.mode != mode {
                try await perform(Requests.enableSpatialAudio(mode: mode)) {
                    $0.spatialAudio = SpatialAudio(isEnabled: true, modeRaw: mode.rawValue)
                }
            }
            let latest = try currentState()
            let write = EqualizerWrite.spatialAudioOff(current: latest.equalizer, hearID: latest.hearID)
            try await perform(Requests.setEqualizer(write), refreshAfter: true) {
                $0.equalizer = write.resultingConfiguration
                $0.spatialAudio.isEnabled = false
            }
        }
    }

    // MARK: Touch controls (04 81, 04 82)

    /// Sets the action for one gesture on one earbud; `nil` disables it. Like OpenSCQ30 and the
    /// Soundcore app, this changes the mapping for the current situation: both buds in use, or
    /// one bud alone (§8.7).
    public func setButtonAction(_ action: ButtonAction?, side: EarbudSide, kind: GestureKind) async throws(SoundcoreError) {
        let state = try currentState()
        if let action, !kind.allowedActions.contains(action) {
            throw .encode(.outOfRange("\(action.displayName) for \(kind.displayName)"))
        }
        let gesture = ButtonGesture(side: side, kind: kind)
        let byte = state.buttons.byte(setting: action, for: gesture, budsLinked: state.tws.isConnected)
        guard byte != state.buttons.raw[gesture.rawValue] else { return }
        try await perform(Requests.setButtonAction(gesture, actionByte: byte)) {
            $0.buttons.raw[gesture.rawValue] = byte
        }
    }

    public func resetButtons() async throws(SoundcoreError) {
        try await perform(Requests.resetButtons(), refreshAfter: true) { _ in }
    }

    // MARK: Dual connection (0B 8x)

    public func setDualConnections(_ enabled: Bool) async throws(SoundcoreError) {
        guard try currentState().dualConnections != enabled else { return }
        try await perform(Requests.setDualConnections(enabled), refreshAfter: true) { $0.dualConnections = enabled }
        if enabled {
            try? await reloadDualConnectionDevices()
        } else {
            dualConnectionDevices = []
        }
    }

    /// Asks the earbuds to connect to another paired device (fire-and-forget, §7.2).
    public func connectDualConnectionDevice(_ address: MACAddress) async throws(SoundcoreError) {
        try await perform(Requests.connectDualConnectionDevice(address)) { _ in }
        await reloadDualConnectionDevicesSoon()
    }

    /// Asks the earbuds to disconnect another device (fire-and-forget, §7.2).
    public func disconnectDualConnectionDevice(_ address: MACAddress) async throws(SoundcoreError) {
        try await perform(Requests.disconnectDualConnectionDevice(address)) { _ in }
        await reloadDualConnectionDevicesSoon()
    }

    /// Removes a pairing from the earbuds. Can't be undone from here.
    public func forgetDualConnectionDevice(_ address: MACAddress) async throws(SoundcoreError) {
        try await perform(Requests.forgetDualConnectionDevice(address)) { _ in }
        dualConnectionDevices.removeAll { $0.address == address }
        await reloadDualConnectionDevicesSoon()
    }

    private func reloadDualConnectionDevicesSoon() async {
        try? await Task.sleep(for: .seconds(2))
        try? await reloadDualConnectionDevices()
    }

    // MARK: Other settings

    public func setAutoPowerOff(enabled: Bool, duration: AutoPowerOffDuration) async throws(SoundcoreError) {
        let target = AutoPowerOff(isEnabled: enabled, durationIndex: duration.rawValue)
        guard try currentState().autoPowerOff != target else { return }
        try await perform(Requests.setAutoPowerOff(enabled: enabled, duration: duration)) { $0.autoPowerOff = target }
    }

    public func setTouchTone(_ enabled: Bool) async throws(SoundcoreError) {
        guard try currentState().touchTone != enabled else { return }
        try await perform(Requests.setTouchTone(enabled)) { $0.touchTone = enabled }
    }

    public func setLowBatteryPrompt(_ enabled: Bool) async throws(SoundcoreError) {
        guard try currentState().lowBatteryPrompt != enabled else { return }
        try await perform(Requests.setLowBatteryPrompt(enabled)) { $0.lowBatteryPrompt = enabled }
    }

    /// LDAC can affect other settings on the earbuds (e.g. dual connection), so the state is
    /// re-read afterwards.
    public func setLDAC(_ enabled: Bool) async throws(SoundcoreError) {
        guard try currentState().ldac != enabled else { return }
        try await perform(Requests.setLDAC(enabled), refreshAfter: true) { $0.ldac = enabled }
    }

    public func setVolumeLimit(enabled: Bool, decibels: UInt8) async throws(SoundcoreError) {
        let current = try currentState().volumeLimit
        guard current.isEnabled != enabled || current.decibels != decibels else { return }
        let frame: Frame
        do {
            frame = try Requests.setVolumeLimit(enabled: enabled, decibels: decibels)
        } catch {
            throw .encode(error)
        }
        try await perform(frame) {
            $0.volumeLimit.isEnabled = enabled
            $0.volumeLimit.decibels = decibels
        }
    }

    public func setVolumeLimitRefreshRate(_ rate: DecibelRefreshRate) async throws(SoundcoreError) {
        guard try currentState().volumeLimit.refreshRate != rate else { return }
        try await perform(Requests.setVolumeLimitRefreshRate(rate)) { $0.volumeLimit.refreshRateRaw = rate.rawValue }
    }
}

extension Duration {
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

/// Receives IOBluetooth's connect/disconnect notifications (Objective-C selectors). On macOS 27
/// these arrive on a private queue, so each one hops to the main actor (see `onMainActor`).
@MainActor
final class ConnectionWatcher: NSObject {
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?
    private let onConnect: (IOBluetoothDevice) -> Void
    private let onDisconnect: (IOBluetoothDevice) -> Void

    init(onConnect: @escaping (IOBluetoothDevice) -> Void, onDisconnect: @escaping (IOBluetoothDevice) -> Void) {
        self.onConnect = onConnect
        self.onDisconnect = onDisconnect
        super.init()
    }

    func start() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(deviceConnected(_:device:))
        )
    }

    func watchDisconnect(of device: IOBluetoothDevice) {
        disconnectNotification?.unregister()
        disconnectNotification = device.register(
            forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:))
        )
    }

    func stop() {
        connectNotification?.unregister()
        disconnectNotification?.unregister()
        connectNotification = nil
        disconnectNotification = nil
    }

    @objc nonisolated func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // IOBluetoothDevice isn't Sendable; pass the address and look the device up on main.
        guard let address = device.addressString else { return }
        onMainActor { [self] in
            if let device = IOBluetoothDevice(addressString: address) { onConnect(device) }
        }
    }

    @objc nonisolated func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        onMainActor { [self] in
            if let device = IOBluetoothDevice(addressString: address) { onDisconnect(device) }
        }
    }

    /// Target for `IOBluetoothDevice.openConnection(_:)`. Auto-connect notices the connection.
    @objc nonisolated func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {}
}
