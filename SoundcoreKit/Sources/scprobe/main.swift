import Foundation
import IOBluetooth
import SoundcoreKit

// scprobe — command-line probe and hardware test harness for Soundcore R60i NC (D1202C).
// It drives the same SoundcoreDevice model the app uses. Every write is one of the packets in
// docs/protocol.md §7.2; after a write it re-reads the state and prints what changed.

@MainActor
func run(_ options: Options) async throws(ProbeError) {
    let log = Log(hexdump: options.hexdump)
    switch options.action {
    case .help:
        print(CLI.usage)
        return
    case .list:
        try printList()
        return
    case .state, .set, .devices:
        break
    }

    let device = SoundcoreDevice()
    device.onEvent = { log.handle($0) }
    let target: IOBluetoothDevice
    do {
        target = try DeviceDiscovery.findDevice(address: options.address)
        try await device.connect(to: target, forceSDPRefresh: options.refreshSDP)
    } catch {
        throw .device(error)
    }

    var failure: ProbeError?
    do {
        try await perform(options, device: device, log: log)
    } catch {
        failure = error
    }
    await device.disconnect()
    if let failure { throw failure }
}

@MainActor
func perform(_ options: Options, device: SoundcoreDevice, log: Log) async throws(ProbeError) {
    guard let state = device.state, let connection = device.connection else { throw .device(.notConnected) }

    switch options.action {
    case .state:
        print(Report.render(state, connection: connection, dualDevices: device.dualConnectionDevices))
    case .devices:
        if !state.dualConnections {
            print("Dual connection is off, so the earbuds don't report a device list.")
        } else {
            do { try await device.reloadDualConnectionDevices() } catch { throw .device(error) }
            print(Report.devices(device.dualConnectionDevices))
        }
    case let .set(setting):
        try await change(setting, device: device, before: state, connection: connection)
    case .list, .help:
        break
    }

    if options.listenSeconds > 0 {
        log.info("Listening for pushed packets for \(options.listenSeconds) s (Ctrl-C to stop)…")
        log.listening = true
        Interrupt.install()
        let deadline = ContinuousClock.now + .milliseconds(Int(options.listenSeconds * 1000))
        while ContinuousClock.now < deadline, !Interrupt.requested, device.isConnected {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if !device.isConnected { log.info("The earbuds closed the channel.") }
    }
}

@MainActor
func change(_ setting: Setting, device: SoundcoreDevice, before: D1202State, connection: ConnectionSummary) async throws(ProbeError) {
    do {
        try await apply(setting, to: device, current: before)
    } catch {
        throw .device(error)
    }
    // Read back until the change shows (the earbuds can take a moment), up to 3 times.
    var after = before
    var mismatch: String?
    for attempt in 0..<3 {
        if attempt > 0 { try? await Task.sleep(for: .milliseconds(300)) }
        do { after = try await device.refreshState() } catch { throw .device(error) }
        mismatch = Verify.mismatch(setting, in: after)
        if mismatch == nil { break }
    }

    let changes = Report.diff(
        before: Report.render(before, connection: connection, dualDevices: []),
        after: Report.render(after, connection: connection, dualDevices: [])
    )
    print(changes.isEmpty ? "No visible change in the state report." : "Changed:\n" + changes.joined(separator: "\n"))
    if let mismatch { throw .notApplied(mismatch) }
}

@MainActor
func apply(_ setting: Setting, to device: SoundcoreDevice, current: D1202State) async throws(SoundcoreError) {
    switch setting {
    case let .ambient(mode): try await device.setAmbientMode(mode)
    case let .noiseCancelingMode(mode): try await device.setNoiseCancelingMode(mode)
    case let .ancLevel(level): try await device.setManualNoiseCancelingLevel(level)
    case let .scene(scene): try await device.setMultiScene(scene)
    case let .transparency(mode): try await device.setTransparencyMode(mode)
    case let .wind(enabled): try await device.setWindNoiseSuppression(enabled)
    case let .realTimeAdaptive(enabled): try await device.setRealTimeAdaptive(enabled)
    case let .eqPreset(preset): try await device.selectEqualizerPreset(preset)
    case let .eqCustom(bands): try await device.setCustomEqualizer(bands)
    case let .spatial(mode):
        try await device.setSpatialAudio(enabled: mode != nil, mode: mode ?? current.spatialAudio.mode ?? .music)
    case let .button(side, kind, action): try await device.setButtonAction(action, side: side, kind: kind)
    case .resetButtons: try await device.resetButtons()
    case let .soundModeCycle(modes): try await device.setSoundModeCycle(modes)
    case let .dualConnections(enabled): try await device.setDualConnections(enabled)
    case let .autoPowerOff(duration):
        try await device.setAutoPowerOff(enabled: duration != nil, duration: duration ?? current.autoPowerOff.duration ?? .thirtyMinutes)
    case let .touchTone(enabled): try await device.setTouchTone(enabled)
    case let .lowBatteryPrompt(enabled): try await device.setLowBatteryPrompt(enabled)
    case let .ldac(enabled): try await device.setLDAC(enabled)
    case let .volumeLimit(decibels):
        let fallback = VolumeLimit.decibelSteps.contains(current.volumeLimit.decibels) ? current.volumeLimit.decibels : 90
        try await device.setVolumeLimit(enabled: decibels != nil, decibels: decibels ?? fallback)
    case let .decibelRefresh(rate): try await device.setVolumeLimitRefreshRate(rate)
    case let .dualConnect(address): try await device.connectDualConnectionDevice(address)
    case let .dualDisconnect(address): try await device.disconnectDualConnectionDevice(address)
    case let .dualForget(address): try await device.forgetDualConnectionDevice(address)
    }
}

/// What the state should show after each setting change. nil = as expected (or nothing to check).
enum Verify {
    static func mismatch(_ setting: Setting, in state: D1202State) -> String? {
        let modes = state.soundModes
        func check(_ ok: Bool, _ what: String) -> String? { ok ? nil : what }
        switch setting {
        case let .ambient(mode): return check(modes.ambient == mode, "sound mode is \(modes.ambient?.displayName ?? "unknown (\(modes.ambientRaw))")")
        case let .noiseCancelingMode(mode): return check(modes.noiseCancelingMode == mode, "ANC mode is raw \(modes.noiseCancelingModeRaw)")
        case let .ancLevel(level): return check(modes.manualLevel == level, "manual level is \(modes.manualLevel)")
        case let .scene(scene): return check(modes.multiScene == scene, "scene is raw \(modes.multiSceneRaw)")
        case let .transparency(mode): return check(modes.transparency == mode, "transparency is raw \(modes.transparencyRaw)")
        case let .wind(enabled): return check(modes.windNoiseSuppression == enabled, "wind suppression is \(modes.windNoiseSuppression)")
        case let .realTimeAdaptive(enabled): return check(modes.realTimeAdaptive == enabled, "real-time adaptive is \(modes.realTimeAdaptive)")
        case let .eqPreset(preset): return check(state.equalizer.presetID == preset.id, "EQ preset is \(state.equalizer.presetName)")
        case let .eqCustom(bands):
            let expected = bands.map(EqualizerConfiguration.byte(forTenths:))
            return check(
                state.equalizer.presetID == EqualizerConfiguration.customPresetID && state.equalizer.leftBytes.map { Array($0.prefix(8)) } == expected,
                "EQ is \(state.equalizer.presetName) \(state.equalizer.left.map { "\($0)" } ?? "-")"
            )
        case let .spatial(mode):
            let spatial = state.spatialAudio
            return mode == nil
                ? check(!spatial.isEnabled, "spatial audio is still on")
                : check(spatial.isEnabled && spatial.mode == mode, "spatial audio is \(spatial.isEnabled ? "on" : "off"), mode raw \(spatial.modeRaw)")
        case let .button(side, kind, action):
            let gesture = ButtonGesture(side: side, kind: kind)
            let nibble = state.buttons.currentNibble(gesture, budsLinked: state.tws.isConnected)
            return check(nibble == (action?.rawValue ?? ButtonAction.disabledNibble), "\(gesture.displayName) is \(ButtonAction.describe(nibble: nibble))")
        case let .soundModeCycle(modes):
            let cycle = state.soundModeCycles.current(budsLinked: state.tws.isConnected)
            return check(Set(cycle.modes) == modes, "cycle is \(cycle.modes.map(\.displayName)) (raw \([state.soundModeCycles.raw].hexString))")
        case let .dualConnections(enabled): return check(state.dualConnections == enabled, "dual connection is \(state.dualConnections)")
        case let .autoPowerOff(duration):
            return duration == nil
                ? check(!state.autoPowerOff.isEnabled, "auto power-off still on")
                : check(state.autoPowerOff.isEnabled && state.autoPowerOff.duration == duration, "auto power-off is \(state.autoPowerOff)")
        case let .touchTone(enabled): return check(state.touchTone == enabled, "touch tone is \(state.touchTone)")
        case let .lowBatteryPrompt(enabled): return check(state.lowBatteryPrompt == enabled, "low-battery prompt is \(state.lowBatteryPrompt)")
        case let .ldac(enabled): return check(state.ldac == enabled, "LDAC is \(state.ldac)")
        case let .volumeLimit(decibels):
            return decibels == nil
                ? check(!state.volumeLimit.isEnabled, "volume limit still on")
                : check(state.volumeLimit.isEnabled && state.volumeLimit.decibels == decibels, "volume limit is \(state.volumeLimit)")
        case let .decibelRefresh(rate): return check(state.volumeLimit.refreshRate == rate, "refresh rate is raw \(state.volumeLimit.refreshRateRaw)")
        case .resetButtons, .dualConnect, .dualDisconnect, .dualForget: return nil
        }
    }
}

@MainActor
func printList() throws(ProbeError) {
    let paired = DeviceDiscovery.pairedDevices()
    guard !paired.isEmpty else { throw .device(.noPairedDevices) }
    print("Paired Bluetooth devices (services from cached SDP records; nothing is connected):")
    for device in paired {
        print("• \(DeviceDiscovery.label(device)) — \(device.isConnected() ? "connected" : "not connected")")
        let services = DeviceDiscovery.services(of: device)
        let picked = DeviceDiscovery.pickService(services)
        if let (service, uuid, suffix) = picked, let channel = service.channelID {
            print("    Soundcore vendor service (model \(suffix)) \(SoundcoreServiceUUID.format(uuid)) on RFCOMM channel \(channel)")
        } else if services.isEmpty {
            print("    no cached SDP records")
        } else {
            print("    no Soundcore vendor RFCOMM service in \(services.count) cached SDP records")
        }
        // For Soundcore devices, show every RFCOMM service too, to help diagnose channel problems.
        guard picked != nil || (device.name ?? "").localizedCaseInsensitiveContains("soundcore") else { continue }
        for service in services {
            guard let channel = service.channelID else { continue }
            let uuids = service.classUUIDs.map(SoundcoreServiceUUID.format).joined(separator: ", ")
            print("      RFCOMM \(String(channel).leftPadded(to: 2))  \(service.name ?? "(unnamed)") — \(uuids.isEmpty ? "no class UUID" : uuids)")
        }
    }
}

/// Ctrl-C during --listen ends listening cleanly so the RFCOMM channel gets closed.
@MainActor
enum Interrupt {
    static var requested = false
    private static var source: DispatchSourceSignal?

    static func install() {
        guard source == nil else { return }
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { Interrupt.requested = true }
        }
        source.resume()
        self.source = source
    }
}

// MARK: - Entry point

let exitCode: Int32
do {
    let options = try CLI.parse(Array(CommandLine.arguments.dropFirst()))
    do {
        try await run(options)
        exitCode = 0
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exitCode = 1
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exitCode = 2
}
exit(exitCode)
