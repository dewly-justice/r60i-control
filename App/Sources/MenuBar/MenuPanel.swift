import AppKit
import SoundcoreKit
import SwiftUI

/// The menu bar panel, built like the system's own menu bar panels (Wi-Fi, Bluetooth, Sound with
/// AirPods): a header, small bold section titles, full-width rows with round icons that fill with
/// the accent color when selected, hover highlights, and the selected mode's options expanding
/// right under it.
///
/// The panel only exists while the earbuds are connected to this Mac (the menu bar icon is
/// hidden otherwise), so besides the controls it only has to cover the moment the control
/// channel opens and the case where it can't.
struct MenuPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader()
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            if let error = model.error {
                ErrorBanner(message: error.message) { model.dismissError() }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            if let state = model.device.state, model.device.isConnected {
                BatteryRow(state: state)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                PanelDivider()
                NoiseControlSection(state: state)
                PanelDivider()
                SwitchRow(title: "Wind Noise Reduction", isOn: model.binding({ $0.soundModes.windNoiseSuppression }, default: false) {
                    try await $0.setWindNoiseSuppression($1)
                }) {
                    if state.soundModes.windDetected {
                        Image(systemName: "wind")
                            .foregroundStyle(.secondary)
                            .help("Wind detected")
                            .accessibilityLabel("Wind detected")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            } else if case .unavailable(let reason) = model.device.status {
                UnavailableNotice(reason: reason)
            }

            PanelDivider()
            VStack(spacing: 0) {
                MenuRow(title: "Earbud Settings…") {
                    model.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                MenuRow(title: "Quit R60i Control") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, 5)
            .padding(.bottom, 5)
        }
        .frame(width: 300)
        // Case battery has no push (docs/protocol.md §6.9), so refresh when the panel opens.
        .task { await model.device.refreshIfStale(olderThan: .seconds(10)) }
    }
}

// MARK: - Header and battery

private struct PanelHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            RoundIcon(symbol: "earbuds", isOn: model.device.isConnected, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.device.deviceName ?? "Soundcore R60i NC")
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if busy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(model.device.isConnected ? "Applying" : "Connecting")
            }
        }
    }

    private var busy: Bool {
        switch model.device.status {
        case .idle, .connecting: true
        default: model.device.pendingWrites > 0
        }
    }

    private var subtitle: String {
        guard let state = model.device.state, model.device.isConnected else { return model.device.status.summary }
        if state.tws.isConnected { return "Connected" }
        return "\(state.tws.hostDeviceRaw == 0 ? "Left" : "Right") earbud only"
    }
}

/// Why the control channel didn't open, and a way to retry. Text lines up with the header title.
private struct UnavailableNotice: View {
    @Environment(AppModel.self) private var model
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The earbuds accept one controller at a time. If the Soundcore app is open on your phone, close it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .help(reason)
                .padding(.leading, 14 + 30 + 10)
                .padding(.trailing, 14)
                .padding(.bottom, 6)
            MenuRow(title: "Try Again") { model.device.retryNow() }
                .padding(.horizontal, 5)
        }
    }
}

// MARK: - Noise control

/// "Noise Control": one row per mode. The selected mode shows its options underneath.
private struct NoiseControlSection: View {
    /// Where row titles start, relative to the section: row padding + icon + spacing.
    static let titleInset: CGFloat = 9 + RoundIcon.rowSize + 9

    @Environment(AppModel.self) private var model
    let state: D1202State

    var body: some View {
        let modes = state.soundModes
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Noise Control")
            ForEach(AmbientSoundMode.menuOrder) { mode in
                let selected = modes.ambient == mode
                IconRow(title: mode.title, symbol: mode.symbol, isOn: selected) {
                    model.perform { try await $0.setAmbientMode(mode) }
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
                if selected {
                    options(for: mode, modes: modes)
                        // Option text lines up with the mode titles; checkmarks hang in the gutter.
                        .padding(.leading, mode == .transparency ? Self.titleInset - CheckRow.textInset : Self.titleInset)
                        .padding(.trailing, 14)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.bottom, 4)
        .animation(.snappy(duration: 0.25), value: modes.raw)
    }

    @ViewBuilder
    private func options(for mode: AmbientSoundMode, modes: SoundModes) -> some View {
        switch mode {
        case .noiseCanceling:
            NoiseCancelingOptions(modes: modes)
        case .transparency:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(TransparencyMode.allCases) { option in
                    CheckRow(title: option.title, isChecked: modes.transparency == option) {
                        model.perform { try await $0.setTransparencyMode(option) }
                    }
                }
            }
        case .normal:
            EmptyView()
        }
    }
}

private struct NoiseCancelingOptions: View {
    @Environment(AppModel.self) private var model
    let modes: SoundModes
    /// The manual level while the slider is being dragged; written on release.
    @State private var levelDraft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SwitchRow(title: "Adaptive", isOn: Binding(
                get: { modes.noiseCancelingMode == .adaptive },
                set: { adaptive in model.perform { try await $0.setNoiseCancelingMode(adaptive ? .adaptive : .manual) } }
            ))

            switch modes.noiseCancelingMode {
            case .manual?:
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.1")
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
                    .controlSize(.small)
                    .accessibilityLabel("Noise cancelling strength")
                    .accessibilityValue("\(Int(levelDraft ?? Double(modes.manualLevel))) of 5")
                    Image(systemName: "speaker.wave.3")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            case .multiScene?:
                HStack {
                    Text("Scene")
                    Spacer()
                    Picker("Scene", selection: model.binding({ $0.soundModes.multiScene ?? .transport }, default: .transport) {
                        try await $0.setMultiScene($1)
                    }) {
                        ForEach(MultiSceneMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
            default:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Building blocks

/// A filled circle with a symbol: accent when on, gray when off (system menu style).
struct RoundIcon: View {
    static let rowSize: CGFloat = 26
    let symbol: String
    let isOn: Bool
    var size: CGFloat = rowSize

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .frame(width: size, height: size)
            .background(Circle().fill(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary)))
    }
}

/// Small bold section title, as in the system menu bar panels.
private struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A selectable row with a round icon, highlighted on hover.
private struct IconRow: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        HoverRow(action: action) {
            HStack(spacing: 9) {
                RoundIcon(symbol: symbol, isOn: isOn)
                Text(title)
                Spacer(minLength: 0)
            }
        }
    }
}

/// A sub-option row with a leading checkmark.
private struct CheckRow: View {
    /// Distance from the row's leading edge to its text: padding + checkmark + spacing.
    static let textInset: CGFloat = 6 + 12 + 6

    let title: String
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        HoverRow(action: action, horizontalPadding: 6, verticalPadding: 3) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .opacity(isChecked ? 1 : 0)
                    .frame(width: 12)
                Text(title)
                Spacer(minLength: 0)
            }
        }
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}

/// Full-width menu row for commands (Settings…, Quit).
struct MenuRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        HoverRow(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A plain button that fills the row and highlights on hover, like a menu item.
private struct HoverRow<Content: View>: View {
    let action: () -> Void
    var horizontalPadding: CGFloat = 9
    var verticalPadding: CGFloat = 4
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct PanelDivider: View {
    var body: some View {
        Divider()
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
    }
}
