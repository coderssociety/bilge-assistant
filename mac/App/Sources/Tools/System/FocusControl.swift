import AppKit
import AsistanCore

/// Turns a Focus (Rahatsız Etme) on or off by running the user's own "Set Focus" shortcut, since
/// macOS offers no public API for it. Without such a shortcut it explains how to make one and
/// offers to open Shortcuts.
enum FocusControl {
    private static let shortcutsApp = "com.apple.shortcuts"

    static func makeCall(toolName: String, turnOn: Bool, command: String) async -> PreparedToolCall {
        let names: [String]
        do {
            names = try await ShortcutsCatalog.names()
        } catch {
            return .unavailable(toolName, message: error.localizedDescription)
        }
        guard let shortcut = FocusShortcut.pick(from: names, turnOn: turnOn, command: command) else {
            let question = turnOn
                ? String(localized: "Odak modunu açabilmem için Kestirmeler'de adında \"Rahatsız Etme Aç\" geçen ve Odak Ayarla eylemini içeren bir kestirme gerekiyor. Kestirmeler'i açayım mı?")
                : String(localized: "Odak modunu kapatabilmem için Kestirmeler'de adında \"Rahatsız Etme Kapat\" geçen ve Odak Ayarla eylemini içeren bir kestirme gerekiyor. Kestirmeler'i açayım mı?")
            return PreparedToolCall(toolName: toolName, argumentsDescription: "openShortcuts", risk: .needsConfirmation,
                                    confirmationQuestion: question, execute: { await openShortcuts() })
        }
        return PreparedToolCall(toolName: toolName, argumentsDescription: shortcut, risk: .safe, confirmationQuestion: nil) {
            let result = try await ShortcutsCatalog.run(shortcut)
            guard !ToolReply.isFailure(result) else { return result }
            return turnOn
                ? String(localized: "'\(shortcut)' kestirmesiyle odak modunu açtım.")
                : String(localized: "'\(shortcut)' kestirmesiyle odak modunu kapattım.")
        }
    }

    @MainActor
    private static func openShortcuts() async -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: shortcutsApp) else {
            return ToolReply.failure(String(localized: "Kestirmeler uygulaması bulunamadı."))
        }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return String(localized: "Kestirmeler açıldı. Yeni bir kestirmeye Odak Ayarla eylemini ekleyip adını koyman yeterli.")
        } catch {
            return ToolReply.failure(String(localized: "Kestirmeler açılamadı."))
        }
    }
}
