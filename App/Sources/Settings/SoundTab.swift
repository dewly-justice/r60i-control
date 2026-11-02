import SoundcoreKit
import SwiftUI

/// Equalizer, spatial audio and LDAC. On the D1202 these interact: an EQ change turns spatial
/// audio off (docs/protocol.md §7.4).
struct SoundTab: View {
    @Environment(AppModel.self) private var model

    private enum Choice: Hashable {
        case preset(UInt16)
        case custom
        case unknown(UInt16)
    }

    var body: some View {
        RequiresConnection { state in
            let bothEarbuds = state.tws.isConnected
            Form {
                Section {
                    Picker("Preset", selection: presetBinding(state)) {
                        ForEach(EqualizerPreset.all, id: \.id) { Text($0.name).tag(Choice.preset($0.id)) }
                        Divider()
                        Text("Custom").tag(Choice.custom)
                        if case let .unknown(id) = choice(state) {
                            Text("Unknown (\(id))").tag(Choice.unknown(id))
                        }
                    }

                    EqualizerEditor(bands: visibleBands(state)) { bands in
                        model.customEqualizer = bands
                        model.perform { try await $0.setCustomEqualizer(bands) }
                    }
                    .padding(.vertical, 4)
                    .disabled(!bothEarbuds)
                } header: {
                    Text("Equalizer")
                } footer: {
                    if !bothEarbuds {
                        Text("Put both earbuds in to change the equalizer.")
                    } else if state.spatialAudio.isEnabled {
                        Text("Dragging a band switches to Custom. Changing the equalizer turns Spatial Audio off.")
                    } else {
                        Text("Dragging a band switches to Custom.")
                    }
                }
                .disabled(!bothEarbuds)

                Section {
                    Toggle("Spatial Audio", isOn: Binding(
                        get: { state.spatialAudio.isEnabled },
                        set: { on in
                            let mode = state.spatialAudio.mode ?? .music
                            model.perform { try await $0.setSpatialAudio(enabled: on, mode: mode) }
                        }
                    ))
                    Picker("Mode", selection: Binding(
                        get: { state.spatialAudio.mode ?? .music },
                        set: { mode in model.perform { try await $0.setSpatialAudio(enabled: true, mode: mode) } }
                    )) {
                        ForEach(SpatialAudioMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!state.spatialAudio.isEnabled)
                } header: {
                    Text("Spatial Audio")
                } footer: {
                    Text(state.ldac
                        ? "Turn off LDAC to use Spatial Audio. The two can't be on together."
                        : "Gaming is the earbuds' low-latency mode.")
                }
                .disabled(state.ldac)

                Section {
                    Toggle("LDAC", isOn: model.binding({ $0.ldac }, default: false) {
                        try await $0.setLDAC($1)
                    })
                    .disabled(state.spatialAudio.isEnabled)
                } header: {
                    Text("Audio Quality")
                } footer: {
                    Text(state.spatialAudio.isEnabled
                        ? "Turn off Spatial Audio to use LDAC. The two can't be on together."
                        : "LDAC is a high-resolution codec that only Android devices use; Macs don't. Switching codecs takes about 10 seconds.")
                }
            }
            .formStyle(.grouped)
        }
    }

    private func choice(_ state: D1202State) -> Choice {
        let id = state.equalizer.presetID
        if id == EqualizerConfiguration.customPresetID { return .custom }
        return EqualizerPreset.all.contains { $0.id == id } ? .preset(id) : .unknown(id)
    }

    private func presetBinding(_ state: D1202State) -> Binding<Choice> {
        Binding(
            get: { choice(state) },
            set: { newChoice in
                switch newChoice {
                case let .preset(id):
                    guard let preset = EqualizerPreset.all.first(where: { $0.id == id }) else { return }
                    model.perform { try await $0.selectEqualizerPreset(preset) }
                case .custom:
                    let bands = model.customEqualizer
                    model.perform { try await $0.setCustomEqualizer(bands) }
                case .unknown:
                    break
                }
            }
        )
    }

    /// The 8 editable bands in tenths of a dB, from the first channel the earbuds report.
    private func visibleBands(_ state: D1202State) -> [Int] {
        let values = state.equalizer.left ?? state.equalizer.right ?? Array(repeating: 0, count: EqualizerConfiguration.bandCount)
        return Array(values.prefix(EqualizerConfiguration.visibleBandCount))
    }
}

/// Eight vertical band sliders (−12…+12 dB). A drag is written when released.
struct EqualizerEditor: View {
    let bands: [Int]
    let commit: ([Int]) -> Void
    @State private var draft: [Double]?

    var body: some View {
        let values = draft ?? bands.map { Double($0) / 10 }
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(EqualizerConfiguration.visibleBandFrequencies.enumerated()), id: \.offset) { index, hz in
                VStack(spacing: 6) {
                    Text(String(format: "%+.1f", values[index]))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    VerticalSlider(
                        value: Binding(
                            get: { values[index] },
                            set: { newValue in
                                var updated = draft ?? bands.map { Double($0) / 10 }
                                updated[index] = newValue
                                draft = updated
                            }
                        ),
                        range: -12...12,
                        step: 0.5
                    ) { editing in
                        guard !editing, let draft else { return }
                        commit(draft.map { Int(($0 * 10).rounded()) })
                        self.draft = nil
                    }
                    .frame(height: 110)
                    .accessibilityLabel("\(frequencyLabel(hz)) band")
                    Text(frequencyLabel(hz))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func frequencyLabel(_ hz: Int) -> String {
        hz >= 1000 ? String(format: "%gk", Double(hz) / 1000) : "\(hz)"
    }
}

/// A vertical slider: track, filled part from 0 dB, and a knob. Supports drag and the
/// accessibility increment/decrement actions.
struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onEditingChanged: (Bool) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let knob: CGFloat = 16
            let usable = height - knob
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let zeroFraction = (0 - range.lowerBound) / (range.upperBound - range.lowerBound)
            let y = knob / 2 + usable * (1 - fraction)
            let zeroY = knob / 2 + usable * (1 - zeroFraction)
            ZStack(alignment: .top) {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                Rectangle()
                    .fill(.tint)
                    .frame(width: 4, height: abs(zeroY - y))
                    .offset(y: min(y, zeroY))
                Circle()
                    .fill(.background)
                    .overlay(Circle().strokeBorder(.tint, lineWidth: dragging ? 3 : 2))
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(y: y - knob / 2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !dragging {
                            dragging = true
                            onEditingChanged(true)
                        }
                        let f = 1 - (gesture.location.y - knob / 2) / usable
                        let raw = range.lowerBound + Double(min(max(f, 0), 1)) * (range.upperBound - range.lowerBound)
                        value = (raw / step).rounded() * step
                    }
                    .onEnded { _ in
                        dragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .accessibilityElement()
        .accessibilityValue(String(format: "%+.1f decibels", value))
        .accessibilityAdjustableAction { direction in
            onEditingChanged(true)
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }
}
