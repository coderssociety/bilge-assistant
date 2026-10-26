import AppKit
import Carbon.HIToolbox

/// A key combination for the listening shortcut, as recorded in the settings.
struct KeyCombination: Codable, Equatable, Sendable {
    /// The virtual key code (kVK_…), the same on every keyboard layout.
    let keyCode: UInt32
    /// NSEvent.ModifierFlags raw value, only ⌘ ⌥ ⌃ ⇧.
    let modifiers: UInt
    /// What the key showed when it was recorded ("B", "Space", "F5").
    let keyName: String

    private static let allowedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    /// In order, F1 first; their key codes are not.
    private static let functionKeys: [Int] = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]
    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    ]

    /// From a key press in the recorder; nil for one that would take ordinary typing or can't be a shortcut. A key
    /// other than an F key needs ⌘ or ⌃: with ⌥ or ⇧ alone it types a character (⌥Q is "@" on a Turkish keyboard).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.allowedModifiers)
        let code = Int(event.keyCode)
        let functionNumber = Self.functionKeys.firstIndex(of: code).map { $0 + 1 }
        guard code != kVK_Escape, code != kVK_Delete,
              functionNumber != nil || !flags.isDisjoint(with: [.command, .control])
        else { return nil }
        let typed = event.charactersIgnoringModifiers?.uppercased()
        // Keys such as Home or Page Up report private-use characters rather than a name.
        let plain = typed.flatMap { $0.count == 1 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } ? $0 : nil }
        let name = Self.namedKeys[code] ?? functionNumber.map { "F\($0)" } ?? plain
        guard let name else { return nil }
        keyCode = UInt32(code)
        modifiers = flags.rawValue
        keyName = name
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// "⌃⌥B", in the order macOS menus use.
    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + keyName
    }

    var carbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}

/// A system-wide shortcut through Carbon's RegisterEventHotKey, which needs no Accessibility permission: the system
/// hands over only this one combination, never the rest of the keyboard.
@MainActor
final class GlobalHotKey {
    enum Failure: Error {
        /// Another app (or this one) already registered it.
        case taken
        case failed(OSStatus)
    }

    private static let signature: OSType = 0x424C_4745 // "BLGE"
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let pressed: @MainActor () -> Void

    init(_ combination: KeyCombination, pressed: @escaping @MainActor () -> Void) throws(Failure) {
        self.pressed = pressed
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { hotKey.pressed() }
            return noErr
        }, 1, &spec, context, &handler)
        guard installed == noErr else { throw .failed(installed) }
        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(combination.keyCode, combination.carbonModifiers, identifier,
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else {
            if let handler { RemoveEventHandler(handler) }
            handler = nil
            throw status == eventHotKeyExistsErr ? .taken : .failed(status)
        }
    }

    isolated deinit {
        unregister()
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil
        handler = nil
    }
}
