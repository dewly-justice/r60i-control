import AppKit
import SoundcoreKit
import SwiftUI

/// One battery reading: glyph and percentage, with the part's name underneath.
struct BatteryGauge: View {
    let name: String
    let level: BatteryLevel
    var charging = false

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: level.symbol(charging: charging) ?? "battery.0percent")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .opacity(level.isAvailable ? 1 : 0.35)
                Text(level.percent.map { "\($0)%" } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(level.isAvailable ? .primary : .secondary)
            }
            .font(.callout)
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var tint: Color {
        guard let percent = level.percent else { return .secondary }
        if charging { return .green }
        return percent <= 20 ? .red : .primary
    }

    private var accessibilityText: String {
        guard let percent = level.percent else { return "\(name): not available" }
        return "\(name): \(percent) percent\(charging ? ", charging" : "")"
    }
}

/// Left, right and case batteries in one row.
struct BatteryRow: View {
    let state: D1202State

    var body: some View {
        HStack(spacing: 0) {
            BatteryGauge(name: "Left", level: state.leftBattery.level, charging: state.leftBattery.isCharging)
            BatteryGauge(name: "Right", level: state.rightBattery.level, charging: state.rightBattery.isCharging)
            BatteryGauge(name: "Case", level: state.caseBattery)
        }
    }
}

/// A title on the leading edge and a small switch on the trailing edge, like the switch rows in
/// the system menu bar panels. `detail` sits right after the title.
struct SwitchRow<Detail: View>: View {
    let title: String
    @Binding var isOn: Bool
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            detail
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

extension SwitchRow where Detail == EmptyView {
    init(title: String, isOn: Binding<Bool>) {
        self.init(title: title, isOn: isOn) { EmptyView() }
    }
}

/// The last action's error, dismissible.
struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(.yellow.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}

/// Opens System Settings → Bluetooth.
@MainActor
func openBluetoothSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
        NSWorkspace.shared.open(url)
    }
}

/// The earbuds' row while they aren't connected, in the style of System Settings' Bluetooth
/// device rows: icon, name, status, and the one action that helps, with guidance underneath.
struct DeviceStatusSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let device = model.device
        Section {
            HStack(spacing: 10) {
                RoundIcon(symbol: "earbuds", isOn: false, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.deviceName ?? "Soundcore R60i NC")
                    Text(device.status.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                action(device)
            }
        } footer: {
            Text(guidance(device.status))
        }
    }

    @ViewBuilder
    private func action(_ device: SoundcoreDevice) -> some View {
        switch device.status {
        case .idle, .connecting:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Connecting")
        case .disconnected:
            Button("Connect") { device.requestBluetoothConnection() }
        case .unavailable:
            Button("Try Again") { device.retryNow() }
        case .bluetoothOff, .notPaired:
            Button("Bluetooth Settings…") { openBluetoothSettings() }
        case .connected:
            EmptyView()
        }
    }

    private func guidance(_ status: SoundcoreDevice.Status) -> String {
        switch status {
        case .idle, .connecting:
            "Reading the earbuds' settings."
        case .disconnected:
            "Earbud settings appear here, and in the menu bar, while the earbuds are connected to this Mac. Take them out of the case, or click Connect."
        case .bluetoothOff:
            "Turn on Bluetooth to use your earbuds with this Mac."
        case .notPaired:
            "Pair your Soundcore R60i NC with this Mac first. If it's paired, allow Bluetooth for R60i Control in Privacy & Security."
        case .unavailable:
            "The earbuds accept one controller at a time. Close the Soundcore app on your phone, then try again."
        case .connected:
            ""
        }
    }
}

/// Device settings, shown only while connected. Settings hides these tabs when the earbuds
/// disconnect, so the placeholder only shows for a moment.
struct RequiresConnection<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder let content: (D1202State) -> Content

    var body: some View {
        if let state = model.device.state, model.device.isConnected {
            content(state)
        } else {
            ContentUnavailableView("Earbuds Not Connected", systemImage: "earbuds")
        }
    }
}
