import AppKit
import SoundcoreKit
import SwiftUI

/// The menu bar panel: battery, sound mode, and the ANC options changed several times a day.
struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let error = model.error {
                ErrorBanner(message: error.message) { model.dismissError() }
            }

            if let state = model.device.state, model.device.isConnected {
                BatteryRow(state: state)
                Divider()
                SoundModeSection(state: state)
            } else {
                ConnectionStatusView()
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        // Case battery has no push (docs/protocol.md §6.9), so refresh when the panel opens.
        .task { await model.device.refreshIfStale(olderThan: .seconds(10)) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "earbuds")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.device.deviceName ?? "Soundcore R60i NC")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.device.pendingWrites > 0 {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Applying")
            }
        }
    }

    private var subtitle: String {
        guard let state = model.device.state, model.device.isConnected else { return "Not connected" }
        if state.tws.isConnected { return "Connected" }
        return "Connected · \(state.tws.hostDeviceRaw == 0 ? "left" : "right") earbud only"
    }

    private var footer: some View {
        VStack(spacing: 2) {
            MenuRow(title: "Settings…", shortcut: "⌘,") {
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            MenuRow(title: "Quit R60i Control", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

/// Sound mode switcher plus the options for the selected mode.
struct SoundModeSection: View {
    @Environment(AppModel.self) private var model
    let state: D1202State
    /// The manual level while the slider is being dragged; written on release.
    @State private var levelDraft: Double?

    var body: some View {
        let modes = state.soundModes
        VStack(alignment: .leading, spacing: 12) {
            ModeSwitcher(selected: modes.ambient) { mode in
                model.perform { try await $0.setAmbientMode(mode) }
            }

            switch modes.ambient {
            case .noiseCanceling?:
                noiseCancelingOptions(modes)
            case .transparency?:
                Picker("Transparency", selection: model.binding({ $0.soundModes.transparency ?? .fullyTransparent }, default: .fullyTransparent) {
                    try await $0.setTransparencyMode($1)
                }) {
                    ForEach(TransparencyMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            default:
                EmptyView()
            }

            SwitchRow(title: "Wind Noise Reduction", symbol: "wind", isOn: model.binding({ $0.soundModes.windNoiseSuppression }, default: false) {
                try await $0.setWindNoiseSuppression($1)
            }) {
                if modes.windDetected {
                    Text("Wind detected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(.snappy, value: modes.raw)
    }

    @ViewBuilder
    private func noiseCancelingOptions(_ modes: SoundModes) -> some View {
        SwitchRow(title: "Adaptive ANC", symbol: "sparkles", isOn: Binding(
            get: { modes.noiseCancelingMode == .adaptive },
            set: { adaptive in model.perform { try await $0.setNoiseCancelingMode(adaptive ? .adaptive : .manual) } }
        ))

        switch modes.noiseCancelingMode {
        case .manual?:
            HStack(spacing: 10) {
                Text("Strength")
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(get: { levelDraft ?? Double(modes.manualLevel) }, set: { levelDraft = $0 }),
                    in: 1...5,
                    step: 1
                ) { editing in
                    guard !editing, let draft = levelDraft else { return }
                    model.perform { try await $0.setManualNoiseCancelingLevel(Int(draft)) }
                    levelDraft = nil
                }
                .accessibilityLabel("Noise cancelling strength")
                Text("\(Int(levelDraft ?? Double(modes.manualLevel)))")
                    .monospacedDigit()
                    .frame(width: 14, alignment: .trailing)
            }
            .font(.callout)
        case .multiScene?:
            Picker("Scene", selection: model.binding({ $0.soundModes.multiScene ?? .transport }, default: .transport) {
                try await $0.setMultiScene($1)
            }) {
                ForEach(MultiSceneMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
        default:
            EmptyView()
        }
    }
}

/// Three round buttons, like Control Center: Noise Cancelling · Normal · Transparency.
struct ModeSwitcher: View {
    let selected: AmbientSoundMode?
    let select: (AmbientSoundMode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AmbientSoundMode.menuOrder) { mode in
                let isSelected = mode == selected
                Button {
                    select(mode)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle().fill(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            )
                        Text(mode.title)
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

/// A full-width, menu-style row with hover highlight.
struct MenuRow: View {
    let title: String
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
