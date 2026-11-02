import SoundcoreKit
import SwiftUI

/// Dual connection (multipoint): on/off and the devices the earbuds know (docs/protocol.md §6.8).
struct ConnectionsTab: View {
    @Environment(AppModel.self) private var model
    @State private var forgetting: DualConnectionDevice?
    private let thisMac = DeviceDiscovery.hostAddress

    var body: some View {
        RequiresConnection { state in
            Form {
                Section {
                    Toggle("Dual Connection", isOn: model.binding({ $0.dualConnections }, default: false) {
                        try await $0.setDualConnections($1)
                    })
                } footer: {
                    Text("Keeps the earbuds connected to two devices at once.")
                }

                if state.dualConnections {
                    Section {
                        if model.device.dualConnectionDevices.isEmpty {
                            Text("The earbuds didn't report any devices.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.device.dualConnectionDevices) { device in
                            row(device)
                        }
                    } header: {
                        HStack {
                            Text("Devices")
                            Spacer()
                            Button {
                                model.perform { try await $0.reloadDualConnectionDevices() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Reload the device list")
                            .accessibilityLabel("Reload devices")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .confirmationDialog(
                "Forget \(forgetting?.name ?? "this device")?",
                isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }),
                presenting: forgetting
            ) { device in
                Button("Forget", role: .destructive) {
                    model.perform { try await $0.forgetDualConnectionDevice(device.address) }
                }
            } message: { _ in
                Text("The earbuds will remove this pairing. The device has to pair again to reconnect.")
            }
        }
    }

    private func row(_ device: DualConnectionDevice) -> some View {
        let isThisMac = device.address == thisMac
        return HStack(spacing: 10) {
            Image(systemName: symbol(for: device.name, isThisMac: isThisMac))
                .font(.title3)
                .foregroundStyle(device.isConnected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name.isEmpty ? "Unnamed Device" : device.name)
                Text([isThisMac ? "This Mac" : nil, device.isConnected ? "Connected" : "Not connected"]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isThisMac {
                if device.isConnected {
                    Button("Disconnect") {
                        model.perform { try await $0.disconnectDualConnectionDevice(device.address) }
                    }
                } else {
                    Button("Connect") {
                        model.perform { try await $0.connectDualConnectionDevice(device.address) }
                    }
                }
                Menu {
                    Button("Forget Device…", role: .destructive) { forgetting = device }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions for \(device.name)")
            }
        }
        .padding(.vertical, 2)
    }

    private func symbol(for name: String, isThisMac: Bool) -> String {
        let lower = name.lowercased()
        if isThisMac || lower.contains("mac") { return "laptopcomputer" }
        if lower.contains("ipad") || lower.contains("tab") { return "ipad" }
        if lower.contains("iphone") || lower.contains("phone") || lower.contains("pixel") || lower.contains("galaxy") { return "iphone" }
        return "dot.radiowaves.left.and.right"
    }
}
