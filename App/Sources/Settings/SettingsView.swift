import SoundcoreKit
import SwiftUI

/// Settings (⌘,): everything the D1202 protocol supports beyond the menu bar panel, grouped
/// like the Soundcore app. As with AirPods in System Settings, the earbud panes are only there
/// while the earbuds are connected; otherwise General shows their status and the app settings.
struct SettingsView: View {
    enum Pane: Hashable {
        case noiseControl, sound, controls, connections, general
    }

    @Environment(AppModel.self) private var model
    @State private var selection = Pane.noiseControl

    var body: some View {
        let connected = model.device.isConnected
        TabView(selection: $selection) {
            if connected {
                Tab("Noise Control", systemImage: "waveform.slash", value: .noiseControl) {
                    NoiseControlTab()
                        .frame(width: 560, height: 580)
                }
                Tab("Sound", systemImage: "slider.vertical.3", value: .sound) {
                    SoundTab()
                        .frame(width: 560, height: 580)
                }
                Tab("Controls", systemImage: "hand.tap", value: .controls) {
                    ControlsTab()
                        .frame(width: 560, height: 580)
                }
                Tab("Connections", systemImage: "laptopcomputer.and.iphone", value: .connections) {
                    ConnectionsTab()
                        .frame(width: 560, height: 580)
                }
            }
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralTab()
                    // Without the earbud sections, the pane is short; let the window shrink.
                    .frame(width: 560, height: connected ? 580 : 340)
            }
        }
        .onChange(of: connected, initial: true) { _, connected in
            if !connected { selection = .general }
        }
        .overlay(alignment: .bottom) {
            if let error = model.error {
                ErrorBanner(message: error.message) { model.dismissError() }
                    .background(.background, in: .rect(cornerRadius: 10))
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: model.error)
    }
}

// MARK: - Noise Control

struct NoiseControlTab: View {
    @Environment(AppModel.self) private var model
    @State private var levelDraft: Double?

    var body: some View {
        RequiresConnection { state in
            let modes = state.soundModes
            Form {
                Section {
                    Picker("Sound Mode", selection: model.binding({ $0.soundModes.ambient ?? .normal }, default: .normal) {
                        try await $0.setAmbientMode($1)
                    }) {
                        ForEach(AmbientSoundMode.menuOrder) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Noise Cancelling") {
                    Picker("Mode", selection: model.binding({ $0.soundModes.noiseCancelingMode ?? .adaptive }, default: .adaptive) {
                        try await $0.setNoiseCancelingMode($1)
                    }) {
                        ForEach([NoiseCancelingMode.adaptive, .manual, .multiScene]) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch modes.noiseCancelingMode {
                    case .adaptive?:
                        Toggle("Real-Time Adaptive ANC", isOn: model.binding({ $0.soundModes.realTimeAdaptive }, default: false) {
                            try await $0.setRealTimeAdaptive($1)
                        })
                    case .manual?:
                        LabeledContent("Strength") {
                            HStack {
                                Slider(
                                    value: Binding(get: { levelDraft ?? Double(modes.manualLevel) }, set: { levelDraft = $0 }),
                                    in: 1...5, step: 1
                                ) { editing in
                                    guard !editing, let draft = levelDraft else { return }
                                    model.perform { try await $0.setManualNoiseCancelingLevel(Int(draft)) }
                                    levelDraft = nil
                                }
                                .frame(width: 200)
                                Text("\(Int(levelDraft ?? Double(modes.manualLevel)))")
                                    .monospacedDigit()
                                    .frame(width: 14)
                            }
                        }
                    case .multiScene?:
                        Picker("Scene", selection: model.binding({ $0.soundModes.multiScene ?? .transport }, default: .transport) {
                            try await $0.setMultiScene($1)
                        }) {
                            ForEach(MultiSceneMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                        .pickerStyle(.radioGroup)
                    case nil:
                        Text("The earbuds report an unknown mode (\(modes.noiseCancelingModeRaw)).")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Transparency") {
                    Picker("Mode", selection: model.binding({ $0.soundModes.transparency ?? .fullyTransparent }, default: .fullyTransparent) {
                        try await $0.setTransparencyMode($1)
                    }) {
                        ForEach(TransparencyMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                }

                Section {
                    Toggle(isOn: model.binding({ $0.soundModes.windNoiseSuppression }, default: false) {
                        try await $0.setWindNoiseSuppression($1)
                    }) {
                        Text("Wind Noise Reduction")
                        if modes.windDetected {
                            Text("Wind detected right now")
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}
