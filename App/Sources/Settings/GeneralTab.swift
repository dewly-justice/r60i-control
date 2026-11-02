import SoundcoreKit
import SwiftUI

/// Earbud settings that don't fit elsewhere, hearing protection, app preferences, and device info.
struct GeneralTab: View {
    @Environment(AppModel.self) private var model
    @State private var openAtLogin = LoginItem.isEnabled

    var body: some View {
        @Bindable var model = model
        Form {
            if let state = model.device.state, model.device.isConnected {
                earbudSections(state)
            } else {
                Section("Earbuds") {
                    ConnectionStatusView()
                }
            }

            Section("App") {
                Toggle("Open at Login", isOn: Binding(
                    get: { openAtLogin },
                    set: { enabled in
                        do {
                            try LoginItem.set(enabled)
                            openAtLogin = LoginItem.isEnabled
                        } catch {
                            model.show("Couldn't change Open at Login: \(error.localizedDescription)")
                        }
                    }
                ))
                Toggle("Show Battery Level in Menu Bar", isOn: $model.showBatteryInMenuBar)
                LabeledContent {
                    ShortcutRecorder(shortcut: $model.cycleShortcut)
                } label: {
                    Text("Cycle Sound Mode")
                    Text(model.shortcutError ?? "Noise Cancelling → Transparency → Normal, from anywhere.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { openAtLogin = LoginItem.isEnabled }
    }

    @ViewBuilder
    private func earbudSections(_ state: D1202State) -> some View {
        Section("Earbuds") {
            Picker("Auto Power Off", selection: Binding(
                get: { state.autoPowerOff.isEnabled ? state.autoPowerOff.duration : nil },
                set: { duration in
                    let keep = state.autoPowerOff.duration ?? .thirtyMinutes
                    model.perform { try await $0.setAutoPowerOff(enabled: duration != nil, duration: duration ?? keep) }
                }
            )) {
                Text("Off").tag(AutoPowerOffDuration?.none)
                ForEach(AutoPowerOffDuration.allCases) { Text($0.title).tag(Optional($0)) }
            }
            Toggle("Touch Tone", isOn: model.binding({ $0.touchTone }, default: false) {
                try await $0.setTouchTone($1)
            })
            Toggle("Low Battery Prompt", isOn: model.binding({ $0.lowBatteryPrompt }, default: false) {
                try await $0.setLowBatteryPrompt($1)
            })
        }

        Section {
            Picker("Volume Limit", selection: Binding(
                get: { state.volumeLimit.isEnabled ? state.volumeLimit.decibels : nil },
                set: { decibels in
                    let keep = VolumeLimit.decibelSteps.contains(state.volumeLimit.decibels) ? state.volumeLimit.decibels : 90
                    model.perform { try await $0.setVolumeLimit(enabled: decibels != nil, decibels: decibels ?? keep) }
                }
            )) {
                Text("Off").tag(UInt8?.none)
                ForEach(VolumeLimit.decibelSteps, id: \.self) { Text("\($0) dB").tag(Optional($0)) }
            }
            Picker("Measure Volume", selection: model.binding({ $0.volumeLimit.refreshRate ?? .realTime }, default: .realTime) {
                try await $0.setVolumeLimitRefreshRate($1)
            }) {
                ForEach(DecibelRefreshRate.allCases) { Text($0.displayName).tag($0) }
            }
        } header: {
            Text("Hearing Protection")
        } footer: {
            Text("Caps how loud the earbuds play.")
        }

        Section("About These Earbuds") {
            LabeledContent("Name", value: model.device.deviceName ?? "—")
            LabeledContent("Model", value: model.device.connection.map { $0.vendorSuffix.hasPrefix("D") ? $0.vendorSuffix : "D\($0.vendorSuffix)" } ?? "—")
            LabeledContent("Firmware") {
                Text("Left \(state.firmwareLeft.displayString ?? "—") · Right \(state.firmwareRight.displayString ?? "—")")
                    .monospacedDigit()
            }
            LabeledContent("Serial Number") {
                Text(state.serialNumber).textSelection(.enabled).monospaced()
            }
            LabeledContent {
                Text("\(state.soundModes.adaptiveStrengthRaw)")
                    .monospacedDigit()
            } label: {
                Text("Adaptive ANC Value")
                Text("Raw value the earbuds report. Its meaning isn't documented.")
            }
            LabeledContent("Last Updated") {
                HStack {
                    if let lastRefresh = model.device.lastRefresh {
                        Text("\(lastRefresh, style: .relative) ago")
                    }
                    Button("Refresh") {
                        model.perform { _ = try await $0.refreshState() }
                    }
                }
            }
        }
    }
}
