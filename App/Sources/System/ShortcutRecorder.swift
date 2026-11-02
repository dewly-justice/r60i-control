import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press a key combination with ⌘, ⌥ or ⌃. Esc cancels.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type Shortcut…" : (shortcut?.display ?? "Record Shortcut"))
                    .monospacedDigit()
                    .frame(minWidth: 110)
            }
            .help(recording ? "Press a key with ⌘, ⌥ or ⌃. Esc cancels." : "Click to set a shortcut")

            if shortcut != nil, !recording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove shortcut")
                .accessibilityLabel("Remove shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if Int(event.keyCode) == kVK_Escape {
                    stop()
                } else if let recorded = Shortcut(event: event) {
                    shortcut = recorded
                    stop()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
