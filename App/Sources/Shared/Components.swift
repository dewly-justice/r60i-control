import AppKit
import SoundcoreKit
import SwiftUI

/// One battery reading: symbol, name, and percentage (or "—" when not reported).
struct BatteryGauge: View {
    let name: String
    let level: BatteryLevel
    var charging = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: level.symbol(charging: charging) ?? "minus")
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(height: 20)
            Text(level.percent.map { "\($0)%" } ?? "—")
                .font(.callout.weight(.medium))
                .monospacedDigit()
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

/// What to show when there is no control connection, by status.
struct ConnectionStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let device = model.device
        VStack(spacing: 10) {
            Image(systemName: symbol(device.status))
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, isActive: device.status == .connecting)
            Text(title(device.status))
                .font(.headline)
            Text(detail(device.status))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions(device)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func actions(_ device: SoundcoreDevice) -> some View {
        switch device.status {
        case .disconnected:
            Button("Connect") { device.requestBluetoothConnection() }
                .buttonStyle(.glassProminent)
        case .unavailable:
            Button("Try Again") { device.retryNow() }
                .buttonStyle(.glass)
        case .bluetoothOff, .notPaired:
            Button("Open Bluetooth Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.glass)
        case .idle, .connecting, .connected:
            EmptyView()
        }
    }

    private func symbol(_ status: SoundcoreDevice.Status) -> String {
        switch status {
        case .bluetoothOff: "antenna.radiowaves.left.and.right.slash"
        case .unavailable: "exclamationmark.triangle"
        default: "earbuds"
        }
    }

    private func title(_ status: SoundcoreDevice.Status) -> String {
        let name = model.device.deviceName ?? "R60i NC"
        return switch status {
        case .idle, .connecting: "Connecting to \(name)…"
        case .bluetoothOff: "Bluetooth Is Off"
        case .notPaired: "No R60i NC Paired"
        case .disconnected: "\(name) Not Connected"
        case .unavailable: "Can't Reach the Earbuds"
        case .connected: "Connected"
        }
    }

    private func detail(_ status: SoundcoreDevice.Status) -> String {
        switch status {
        case .idle, .connecting:
            "Reading the earbuds' settings."
        case .bluetoothOff:
            "Turn on Bluetooth to control your earbuds."
        case .notPaired:
            "Pair your Soundcore R60i NC in Bluetooth settings first."
        case .disconnected:
            "Take the earbuds out of the case. They connect automatically when this Mac is their audio device."
        case let .unavailable(reason):
            "\(reason)\nIf the Soundcore app is open on your phone, close it: the earbuds accept only one controller at a time."
        case .connected:
            ""
        }
    }
}

/// Placeholder for device settings while there's no connection.
struct RequiresConnection<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder let content: (D1202State) -> Content

    var body: some View {
        if let state = model.device.state, model.device.isConnected {
            content(state)
        } else {
            ConnectionStatusView()
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
