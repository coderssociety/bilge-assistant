import AppKit
import ApplicationServices

enum AccessibilityError: LocalizedError {
    case notTrusted
    case noWindow

    var errorDescription: String? {
        switch self {
        case .notTrusted:
            "Bunun için Erişilebilirlik izni gerekiyor. Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik'ten Bilge'yi aç."
        case .noWindow:
            "Öndeki pencereyi bulamadım."
        }
    }
}

/// Accessibility (AX) access to other apps' windows and text, and synthetic key events.
@MainActor
enum AccessibilityControl {
    /// Prompts once; macOS then lists Bilge under Privacy & Security > Accessibility.
    static func requireTrust() throws {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { throw AccessibilityError.notTrusted }
    }

    /// The frontmost app other than Bilge itself.
    static func frontApplication() -> NSRunningApplication? {
        let own = ProcessInfo.processInfo.processIdentifier
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own else { return nil }
        return front
    }

    static func focusedWindow() throws -> AXUIElement {
        try requireTrust()
        guard let app = frontApplication() else { throw AccessibilityError.noWindow }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = attribute(element, kAXFocusedWindowAttribute) else { throw AccessibilityError.noWindow }
        return window as! AXUIElement
    }

    static func selectedText() throws -> String? {
        try requireTrust()
        let system = AXUIElementCreateSystemWide()
        guard let focused = attribute(system, kAXFocusedUIElementAttribute) else { return nil }
        return attribute(focused as! AXUIElement, kAXSelectedTextAttribute) as? String
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    /// Types text into the focused field as Unicode key events; no Return is ever sent.
    static func type(_ text: String) async throws {
        try requireTrust()
        let source = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.replacingOccurrences(of: "\n", with: " ").utf16)
        for chunk in stride(from: 0, to: units.count, by: 16).map({ Array(units[$0..<min($0 + 16, units.count)]) }) {
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event?.post(tap: .cghidEventTap)
            }
            try await Task.sleep(for: .milliseconds(8))
        }
    }

    /// Sends ⌘C, for apps that don't expose their selection through AX.
    static func copySelection() {
        let source = CGEventSource(stateID: .hidSystemState)
        let cKey: CGKeyCode = 8
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
