import AppKit
import IOKit.hidsystem

/// Brightness and media keys, posted the way the keyboard sends them: system-defined events
/// (subtype 8) carrying the NX key code. Posting events needs the Accessibility permission.
@MainActor
enum SystemKeys {
    private static let auxiliaryKeySubtype: Int16 = 8
    private static let keyDownState = 0xA
    private static let keyUpState = 0xB

    static func press(_ key: Int32) throws {
        try AccessibilityControl.requireTrust()
        for state in [keyDownState, keyUpState] {
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: auxiliaryKeySubtype,
                data1: (Int(key) << 16) | (state << 8), data2: -1)
            guard let cgEvent = event?.cgEvent else { throw SystemKeyError.notSent }
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    enum SystemKeyError: LocalizedError {
        case notSent
        var errorDescription: String? { String(localized: "Tuş gönderilemedi.") }
    }
}
