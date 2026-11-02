import Foundation
import SoundcoreKit

enum Report {
    static func render(_ state: D1202State, connection: ConnectionSummary, dualDevices: [DualConnectionDevice]) -> String {
        var out: [String] = []
        func row(_ label: String, _ value: String, indent: Int = 2, width: Int = 20) {
            let padded = label.padding(toLength: width, withPad: " ", startingAt: 0)
            out.append(String(repeating: " ", count: indent) + padded + value)
        }

        // Device
        out.append(connection.displayName)
        row("Service", "Soundcore vendor service \(SoundcoreServiceUUID.format(connection.serviceUUID)), RFCOMM channel \(connection.channelID)")
        row("Model check", "\(connection.modelConfirmed ? "OK" : "NOT CONFIRMED") — \(connection.modelNote)")
        row("Firmware", "left \(state.firmwareLeft.displayString ?? "—") · right \(state.firmwareRight.displayString ?? "—")")
        row("Serial", state.serialNumber)
        out.append("")

        // Battery
        out.append("Battery")
        row("Left", battery(state.leftBattery))
        row("Right", battery(state.rightBattery))
        row("Case", state.caseBattery.percent.map { "\($0)%" } ?? "unavailable")
        row("Earbuds", state.tws.isConnected ? "linked (host: \(state.tws.hostDeviceName))" : "not linked (only \(state.tws.hostDeviceName) connected)")
        out.append("")

        // Sound modes
        let modes = state.soundModes
        out.append("Sound mode".padding(toLength: 22, withPad: " ", startingAt: 0) + (modes.ambient?.displayName ?? "unknown (\(modes.ambientRaw))"))
        let ncMode = modes.noiseCancelingMode?.displayName ?? "unknown (\(modes.noiseCancelingModeRaw))"
        let scene = modes.multiScene?.displayName ?? "unknown (\(modes.multiSceneRaw))"
        row("ANC mode", modes.noiseCancelingMode == .multiScene ? "\(ncMode) → \(scene)" : "\(ncMode) (multi-scene setting: \(scene))")
        row("Manual ANC level", "\(modes.manualLevelRaw) / 5")
        row("Adaptive strength", "\(modes.adaptiveStrength?.displayName ?? "raw \(modes.adaptiveStrengthRaw) (OpenSCQ30 only names 0–2)") (read-only, reported by earbuds)")
        row("Transparency", modes.transparency?.displayName ?? "unknown (\(modes.transparencyRaw))")
        row("Wind noise", "suppression \(onOff(modes.windNoiseSuppression)), wind \(modes.windDetected ? "detected" : "not detected")")
        row("Real-time adaptive", onOff(modes.realTimeAdaptive))
        row("Raw bytes", modes.raw.hexString)
        out.append("")

        // Equalizer
        let eq = state.equalizer
        out.append("Equalizer".padding(toLength: 22, withPad: " ", startingAt: 0) + "\(eq.presetName) (preset id \(eq.presetID == EqualizerConfiguration.customPresetID ? "0xFEFE" : String(eq.presetID)))")
        let header = EqualizerConfiguration.visibleBandFrequencies.map { hz in
            (hz >= 1000 ? String(format: "%gk", Double(hz) / 1000) : "\(hz)").leftPadded(to: 6)
        }.joined() + "  │ hidden"
        row("Band (Hz)", header, width: 14)
        row("Left", bands(eq.left), width: 14)
        row("Right", bands(eq.right), width: 14)
        out.append("")

        // Buttons
        out.append("Touch controls".padding(toLength: 22, withPad: " ", startingAt: 0) + "both buds".padding(toLength: 20, withPad: " ", startingAt: 0) + "single bud")
        for gesture in ButtonGesture.allCases {
            let linked = ButtonAction.describe(nibble: state.buttons.linkedNibble(gesture))
            let solo = ButtonAction.describe(nibble: state.buttons.soloNibble(gesture))
            row(gesture.displayName, linked.padding(toLength: 20, withPad: " ", startingAt: 0) + solo)
        }
        out.append("")

        // Other
        out.append("Other")
        row("Touch tone", onOff(state.touchTone))
        row("Low-battery prompt", onOff(state.lowBatteryPrompt))
        row("LDAC", onOff(state.ldac))
        row("Dual connection", onOff(state.dualConnections))
        row("Auto power-off", state.autoPowerOff.isEnabled
            ? "on, \(state.autoPowerOff.minutes.map { "\($0) min" } ?? "unknown index \(state.autoPowerOff.durationIndex)")"
            : "off")
        row("Volume limit", "\(onOff(state.volumeLimit.isEnabled)) (\(state.volumeLimit.decibels) dB, refresh \(state.volumeLimit.refreshRateName))")
        row("Spatial audio", "\(onOff(state.spatialAudio.isEnabled)) (mode \(state.spatialAudio.mode?.displayName ?? "unknown (\(state.spatialAudio.modeRaw))"))")
        row("HearID", "\(state.hearID.isEnabled ? "on" : "off") (type byte \([state.hearID.typeRaw].hexString))")
        row("State packet", "\(state.body.count)-byte body (\(state.body.count - D1202StateLayout.minimumBodyLength) unparsed trailing bytes)")

        if state.dualConnections, !dualDevices.isEmpty {
            out.append("")
            out.append(devices(dualDevices))
        }
        return out.joined(separator: "\n")
    }

    static func devices(_ devices: [DualConnectionDevice]) -> String {
        guard !devices.isEmpty else { return "Dual-connection devices: none reported" }
        var lines = ["Dual-connection devices"]
        for device in devices {
            lines.append("  \(device.isConnected ? "●" : "○") \(device.name.isEmpty ? "(unnamed)" : device.name)  \(device.address)\(device.isConnected ? "  connected" : "")")
        }
        return lines.joined(separator: "\n")
    }

    /// Lines of `after` that differ from the same line in `before`, as "before → after".
    static func diff(before: String, after: String) -> [String] {
        let old = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let new = after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var section = ""
        var changes: [String] = []
        for (index, line) in new.enumerated() {
            if !line.hasPrefix(" "), !line.isEmpty { section = String(line.prefix(22)).trimmingCharacters(in: .whitespaces) }
            let previous = index < old.count ? old[index] : ""
            guard line != previous else { continue }
            changes.append("  [\(section)]\n    − \(previous.trimmingCharacters(in: .whitespaces))\n    + \(line.trimmingCharacters(in: .whitespaces))")
        }
        return changes
    }

    static func battery(_ battery: EarbudBattery) -> String {
        guard let percent = battery.level.percent else { return "not connected" }
        return "\(percent)%" + (battery.isCharging ? "  charging" : "")
    }

    static func bands(_ values: [Int]?) -> String {
        guard let values else { return "(not present)" }
        func format(_ tenths: Int) -> String { String(format: "%+.1f", Double(tenths) / 10).leftPadded(to: 6) }
        let visible = values.prefix(EqualizerConfiguration.visibleBandCount).map(format).joined()
        let hidden = values.dropFirst(EqualizerConfiguration.visibleBandCount).map(format).joined()
        return visible + "  │" + hidden
    }

    static func onOff(_ value: Bool) -> String { value ? "on" : "off" }

    /// One-line summary of a pushed packet (docs/protocol.md §6).
    static func describePush(_ frame: Frame) -> String {
        let body = frame.body
        let summary: String
        switch frame.command {
        case .soundModes:
            if let modes = try? SoundModes(bytes: body) {
                summary = "sound modes: \(modes.ambient?.displayName ?? "unknown (\(modes.ambientRaw))"), "
                    + "ANC \(modes.noiseCancelingMode?.displayName ?? "?"), manual \(modes.manualLevelRaw), "
                    + "adaptive \(modes.adaptiveStrength?.displayName ?? "?"), wind suppression \(onOff(modes.windNoiseSuppression))"
            } else {
                summary = "sound modes (short body)"
            }
        case .batteryLevel where body.count >= 2:
            summary = "battery: left \(BatteryLevel(raw: body[0]).percent.map { "\($0)%" } ?? "—"), right \(BatteryLevel(raw: body[1]).percent.map { "\($0)%" } ?? "—")"
        case .batteryCharging where body.count >= 2:
            summary = "charging: left \(body[0] == 1 ? "yes" : "no"), right \(body[1] == 1 ? "yes" : "no")"
        case .twsStatus where body.count >= 2:
            summary = "TWS: \(body[1] == 1 ? "linked" : "not linked"), host \(body[0] == 0 ? "left" : body[0] == 1 ? "right" : "?")"
        case .ldacState where body.count >= 1:
            summary = "LDAC \(onOff(body[0] == 1))"
        case .state:
            summary = (try? D1202State(body: body)).map { "full state (sound mode \($0.soundModes.ambient?.displayName ?? "?"))" } ?? "full state (unparseable)"
        default:
            summary = frame.command.name ?? "unknown command"
        }
        return "push ← \(frame.command)  \(summary)  [body \(body.hexString)]"
    }
}

extension String {
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
