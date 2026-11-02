import AppKit
import Observation
import os
import SoundcoreKit
import SwiftUI

/// App-wide state: the earbuds (`SoundcoreDevice`), the last error, and app preferences.
@MainActor
@Observable
final class AppModel {
    struct ActionError: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    let device = SoundcoreDevice()

    /// The last failed action, shown as a banner until dismissed or replaced.
    private(set) var error: ActionError?

    var showBatteryInMenuBar: Bool {
        didSet { defaults.set(showBatteryInMenuBar, forKey: Keys.showBattery) }
    }

    /// Global shortcut that cycles Noise Cancelling → Transparency → Normal.
    var cycleShortcut: Shortcut? {
        didSet {
            defaults.set(try? JSONEncoder().encode(cycleShortcut), forKey: Keys.cycleShortcut)
            shortcutError = hotKey.register(cycleShortcut) ? nil : "That shortcut is taken by another app."
        }
    }
    private(set) var shortcutError: String?

    /// The menu bar icon is shown only while the earbuds are connected to this Mac, as macOS does
    /// for AirPods. That includes the few seconds the control channel takes to open, and the case
    /// where it can't open (the panel then says why).
    var showsMenuBarItem: Bool { device.status.earbudsConnectedToMac }

    /// Whether the app has ever connected to the earbuds (it remembers their address).
    let hasConnectedBefore: Bool

    /// Opens the Settings window; set by `AppDelegate`, which hosts it.
    @ObservationIgnored var openSettingsHandler: () -> Void = {}

    func openSettings() { openSettingsHandler() }

    /// On-device live translation (stands in for the Soundcore app's AI Translation).
    let translator = LiveTranslator()

    /// Opens the Live Translation window; set by `AppDelegate`.
    @ObservationIgnored var openTranslationHandler: () -> Void = {}

    func openTranslation() { openTranslationHandler() }

    /// The last custom EQ (8 bands, tenths of a dB). The earbuds forget custom values when a
    /// preset is chosen, so the app keeps them to restore "Custom".
    var customEqualizer: [Int] {
        didSet { defaults.set(customEqualizer, forKey: Keys.customEqualizer) }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let hotKey = GlobalHotKey()
    @ObservationIgnored private let log = Logger(subsystem: "dev.local.R60iControl", category: "earbuds")
    @ObservationIgnored private var errorDismissal: Task<Void, Never>?

    private enum Keys {
        static let showBattery = "showBatteryInMenuBar"
        static let cycleShortcut = "cycleShortcut"
        static let customEqualizer = "customEqualizer"
        static let deviceAddress = "deviceAddress"
    }

    init() {
        showBatteryInMenuBar = defaults.object(forKey: Keys.showBattery) as? Bool ?? false
        cycleShortcut = (defaults.data(forKey: Keys.cycleShortcut)).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
        let savedEQ = defaults.array(forKey: Keys.customEqualizer) as? [Int] ?? []
        customEqualizer = savedEQ.count == EqualizerConfiguration.visibleBandCount
            ? savedEQ : Array(repeating: 0, count: EqualizerConfiguration.visibleBandCount)

        device.preferredAddress = defaults.string(forKey: Keys.deviceAddress)
        hasConnectedBefore = device.preferredAddress != nil
        device.onEvent = { [log] event in
            switch event {
            case let .info(message): log.info("\(message, privacy: .public)")
            case let .push(frame): log.debug("push \(frame.command.description, privacy: .public) \(frame.body.hexString, privacy: .public)")
            case let .link(.sent(_, note)) where note.hasPrefix("01 01") || note.hasPrefix("0B 01 "):
                log.debug("→ \(note, privacy: .public)")
            case let .link(.sent(bytes, note)):
                // Writes are user actions: keep them in the persisted log.
                log.info("→ \(note, privacy: .public) \(bytes.hexString, privacy: .public)")
            case let .link(.dropped(bytes, reason)): log.error("dropped \(bytes.count) bytes: \(reason, privacy: .public)")
            case .link: break
            }
        }

        hotKey.onPress = { [weak self] in self?.cycleSoundMode() }
        _ = hotKey.register(cycleShortcut)

        // After sleep, check the connection right away instead of waiting for the next poll.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.device.retryNow() }
        }

        device.startAutoConnect()
        observeConnectedAddress()
    }

    /// Remembers which earbuds we connected to, so a second paired pair doesn't steal focus.
    private func observeConnectedAddress() {
        withObservationTracking {
            _ = device.status
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.device.isConnected, let address = self.device.deviceAddress {
                    self.defaults.set(address, forKey: Keys.deviceAddress)
                }
                self.observeConnectedAddress()
            }
        }
    }

    // MARK: Actions

    /// Runs one device action and turns a failure into the error banner.
    func perform(_ action: @escaping @MainActor (SoundcoreDevice) async throws -> Void) {
        Task {
            do {
                try await action(device)
            } catch let error as SoundcoreError {
                show(error.description)
            } catch {
                show(error.localizedDescription)
            }
        }
    }

    func cycleSoundMode() {
        guard device.isConnected else {
            NSSound.beep()
            return
        }
        perform { try await $0.cycleAmbientMode() }
    }

    func show(_ message: String) {
        log.error("\(message, privacy: .public)")
        error = ActionError(message: message)
        errorDismissal?.cancel()
        errorDismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.error = nil
        }
    }

    func dismissError() {
        errorDismissal?.cancel()
        error = nil
    }

    /// A binding that reads from the device state and writes through a device action.
    func binding<Value>(
        _ read: @escaping (D1202State) -> Value,
        default fallback: Value,
        write: @escaping @MainActor (SoundcoreDevice, Value) async throws -> Void
    ) -> Binding<Value> {
        Binding(
            get: { [device] in device.state.map(read) ?? fallback },
            set: { [weak self] value in self?.perform { try await write($0, value) } }
        )
    }
}
