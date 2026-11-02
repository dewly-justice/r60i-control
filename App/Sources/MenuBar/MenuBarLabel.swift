import SoundcoreKit
import SwiftUI

/// The menu bar icon: the current sound mode while connected, earbuds otherwise.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let device = model.device
        if device.isConnected, let state = device.state {
            let mode = state.soundModes.ambient ?? .normal
            if model.showBatteryInMenuBar, let percent = state.lowestEarbudPercent {
                Label("\(percent)%", systemImage: mode.symbol)
                    .labelStyle(.titleAndIcon)
                    .accessibilityLabel("R60i NC, \(mode.title), battery \(percent) percent")
            } else {
                Image(systemName: mode.symbol)
                    .accessibilityLabel("R60i NC, \(mode.title)")
            }
        } else {
            Image(systemName: "earbuds")
                .accessibilityLabel("R60i NC, not connected")
        }
    }
}
