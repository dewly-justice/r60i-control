import SwiftUI

/// Menu bar app for the Soundcore R60i NC. The menu bar panel holds the controls used every day;
/// everything else lives in Settings (⌘,).
@main
struct R60iControlApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
