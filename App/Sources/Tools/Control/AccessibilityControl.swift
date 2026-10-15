import AppKit
import ApplicationServices

enum AccessibilityError: LocalizedError {
    case notTrusted
    case noWindow
    case focusChanged

    var errorDescription: String? {
        switch self {
        case .notTrusted:
            String(localized: "Bunun için Erişilebilirlik izni gerekiyor. Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik'ten Bilge'yi aç.")
        case .noWindow:
            String(localized: "Öndeki pencereyi bulamadım.")
        case .focusChanged:
            String(localized: "Yazarken öndeki uygulama değişti, yazmayı durdurdum.")
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

    /// The text of the focused field, e.g. a document's text view.
    static func focusedValue() throws -> String? {
        try requireTrust()
        let system = AXUIElementCreateSystemWide()
        guard let focused = attribute(system, kAXFocusedUIElementAttribute) else { return nil }
        return attribute(focused as! AXUIElement, kAXValueAttribute) as? String
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

    /// Types already-sanitized text (`TypedText`) as Unicode key events, only while `pid` stays frontmost:
    /// if focus moves to another app mid-way, typing stops.
    static func type(_ text: String, into pid: pid_t) async throws {
        try requireTrust()
        let source = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        for chunk in stride(from: 0, to: units.count, by: 16).map({ Array(units[$0..<min($0 + 16, units.count)]) }) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { throw AccessibilityError.focusChanged }
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event?.post(tap: .cghidEventTap)
            }
            try await Task.sleep(for: .milliseconds(8))
        }
    }

    /// One key press (down and up) to the front app. Use layout-independent keys (Tab, arrows, Page
    /// Down) or letters that sit in the same place on Turkish and US layouts.
    static func press(_ key: CGKeyCode, flags: CGEventFlags = []) throws {
        try requireTrust()
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
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
