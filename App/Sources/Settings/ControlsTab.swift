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
                Section {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            Text("")
                            Text("Left").font(.headline)
                            Text("Right").font(.headline)
                        }
                        ForEach(GestureKind.allCases) { kind in
                            GridRow {
                                Text(kind.displayName)
                                    .gridColumnAlignment(.leading)
                                picker(state: state, side: .left, kind: kind)
                                picker(state: state, side: .right, kind: kind)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Touch Controls")
                } footer: {
                    Text(linked
                        ? "These are the controls while both earbuds are in use."
                        : "Only one earbud is in use, so these are the single-earbud controls. Use both earbuds to edit the two-earbud controls.")
                }

                Section {
                    Button("Reset Controls to Defaults…", role: .destructive) {
                        confirmingReset = true
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

    private func picker(state: D1202State, side: EarbudSide, kind: GestureKind) -> some View {
        let gesture = ButtonGesture(side: side, kind: kind)
        let nibble = state.buttons.currentNibble(gesture, budsLinked: state.tws.isConnected)
        let current: Choice = nibble == ButtonAction.disabledNibble
            ? .disabled
            : ButtonAction(rawValue: nibble).map(Choice.action) ?? .unknown(nibble)
        return Picker("\(side.displayName) \(kind.displayName)", selection: Binding(
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
        .labelsHidden()
        .frame(width: 170)
    }
}
