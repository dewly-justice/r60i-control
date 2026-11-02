import SwiftUI

/// Menu bar app for the Soundcore R60i NC. Like AirPods in macOS, it only shows up while the
/// earbuds are connected to this Mac: the menu bar icon appears when they connect and goes away
/// when they disconnect. The panel holds the controls used every day; everything else lives in
/// Settings (⌘,), which `AppDelegate` hosts so it can also open when the icon is hidden.
@main
struct R60iControlApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        let model = appDelegate.model
        MenuBarExtra(isInserted: .constant(model.showsMenuBarItem)) {
            MenuPanel()
                .environment(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
