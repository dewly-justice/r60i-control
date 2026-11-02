import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut, stored with how it was shown when recorded.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
    var carbonModifiers: UInt32
    var display: String

    /// Builds a shortcut from a key press. Needs at least ⌘, ⌥ or ⌃ so it doesn't steal typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        var carbon: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); symbols += "⌘" }
        keyCode = UInt32(event.keyCode)
        carbonModifiers = carbon
        display = symbols + Self.keyName(event)
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: break
        }
        let functionKeys: [Int: String] = [
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = functionKeys[Int(event.keyCode)] { return name }
        return event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }
}

/// A system-wide hot key (Carbon `RegisterEventHotKey`). Works in the sandbox and doesn't need
/// Accessibility permission.
@MainActor
final class GlobalHotKey {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Registers `shortcut` (nil just unregisters). Returns false if the system refused it.
    @discardableResult
    func register(_ shortcut: Shortcut?) -> Bool {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        guard let shortcut else { return true }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x5236_3069), id: 1) // 'R60i'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref
        return status == noErr
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    fileprivate func fire() {
        onPress?()
    }
}

/// Carbon delivers hot-key events on the main thread (application event target).
private func hotKeyHandler(_: EventHandlerCallRef?, _: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotKey.fire() }
    return noErr
}
