import AppKit
import SwiftUI

/// Owns the model and the app's windows (Settings, Live Translation).
///
/// The scenes are hosted with `NSHostingSceneRepresentation` (macOS 26) rather than declared in
/// the `App`, so code without a view can open them: the menu bar icon is hidden while the
/// earbuds are away, and reopening the app from Finder or Spotlight then shows Settings.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    /// Keeps the hosted scenes alive.
    private var sceneRepresentation: AnyObject?
    private var sceneEnvironment: () -> EnvironmentValues? = { nil }

    func applicationWillFinishLaunching(_ notification: Notification) {
        let scene = NSHostingSceneRepresentation { [model] in
            Settings { SettingsRoot(model: model) }
            Window("Live Translation", id: LiveTranslationView.windowID) {
                LiveTranslationView()
                    .environment(model)
            }
            .defaultSize(width: 640, height: 520)
            .defaultLaunchBehavior(.suppressed)
        }
        NSApp.addSceneRepresentation(scene)
        sceneRepresentation = scene
        sceneEnvironment = { [weak scene] in scene?.environment }
        model.openSettingsHandler = { [weak self] in self?.showSettings() }
        model.openTranslationHandler = { [weak self] in self?.showTranslation() }
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
        sceneEnvironment()?.openSettings()
    }

    func showTranslation() {
        NSApp.activate()
        sceneEnvironment()?.openWindow(id: LiveTranslationView.windowID)
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
