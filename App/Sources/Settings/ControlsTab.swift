import SoundcoreKit
import SwiftUI

/// Touch controls: one action per gesture per earbud (docs/protocol.md §8.7).
struct ControlsTab: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingReset = false

    private enum Choice: Hashable {
        case disabled
        case action(ButtonAction)
        case unknown(UInt8)
    }

    var body: some View {
        RequiresConnection { state in
            let linked = state.tws.isConnected
            Form {
                // One section per earbud, one row per gesture, as in System Settings → AirPods.
                Section("Left Earbud") {
                    gestureRows(state: state, side: .left)
                }
                Section {
                    gestureRows(state: state, side: .right)
                } header: {
                    Text("Right Earbud")
                } footer: {
                    Text(linked
                        ? "These controls apply while you wear both earbuds."
                        : "You're wearing one earbud, so these are the one-earbud controls. Wear both to edit the two-earbud controls.")
                }

                Section {
                    LabeledContent {
                        Button("Reset…") { confirmingReset = true }
                    } label: {
                        Text("Reset Touch Controls")
                        Text("Restores the default action for every gesture on both earbuds.")
                    }
                }
            }
            .formStyle(.grouped)
            .confirmationDialog("Reset all touch controls to their defaults?", isPresented: $confirmingReset) {
                Button("Reset", role: .destructive) {
                    model.perform { try await $0.resetButtons() }
                }
            } message: {
                Text("This replaces the controls on both earbuds.")
            }
        }
    }

    @ViewBuilder
    private func gestureRows(state: D1202State, side: EarbudSide) -> some View {
        // Row IDs must differ between the two sections, or the form mixes up their rows.
        ForEach(GestureKind.allCases.map { ButtonGesture(side: side, kind: $0) }, id: \.self) { gesture in
            picker(state: state, side: gesture.side, kind: gesture.kind)
        }
    }

    private func picker(state: D1202State, side: EarbudSide, kind: GestureKind) -> some View {
        let gesture = ButtonGesture(side: side, kind: kind)
        let nibble = state.buttons.currentNibble(gesture, budsLinked: state.tws.isConnected)
        let current: Choice = nibble == ButtonAction.disabledNibble
            ? .disabled
            : ButtonAction(rawValue: nibble).map(Choice.action) ?? .unknown(nibble)
        return Picker(kind.title, selection: Binding(
            get: { current },
            set: { choice in
                let action: ButtonAction?
                switch choice {
                case .disabled: action = nil
                case let .action(value): action = value
                case .unknown: return
                }
                model.perform { try await $0.setButtonAction(action, side: side, kind: kind) }
            }
        )) {
            Text("None").tag(Choice.disabled)
            Divider()
            ForEach(kind.allowedActions) { Text($0.title).tag(Choice.action($0)) }
            if case let .unknown(raw) = current {
                Text("Unknown (\(raw))").tag(Choice.unknown(raw))
            }
        }
        .accessibilityLabel("\(side.displayName) \(kind.title)")
    }
}
