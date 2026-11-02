import AppKit
import SwiftUI

/// Owns the model and the Settings window.
///
/// The Settings scene is hosted with `NSHostingSceneRepresentation` (macOS 26) rather than
/// declared in the `App`, so code without a view can open it: the menu bar icon is hidden while
/// the earbuds are away, and reopening the app from Finder or Spotlight then shows Settings.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var settingsScene: NSHostingSceneRepresentation<Settings<SettingsRoot>>?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let scene = NSHostingSceneRepresentation { [model] in
            Settings { SettingsRoot(model: model) }
        }
        NSApp.addSceneRepresentation(scene)
        settingsScene = scene
        model.openSettingsHandler = { [weak self] in self?.showSettings() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Until the app has connected once, nothing of it would be visible. Give auto-connect a
        // moment, then open Settings to say what it's waiting for.
        guard !model.hasConnectedBefore else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !self.model.showsMenuBarItem else { return }
            self.showSettings()
        }
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func showSettings() {
        NSApp.activate()
        settingsScene?.environment.openSettings()
    }
}

/// The Settings window's root view, with the model in the environment.
struct SettingsRoot: View {
    let model: AppModel

    var body: some View {
        SettingsView()
            .environment(model)
    }
}
