import AppKit
import AsistanCore

/// Hands-free dictation into one app: what was typed (so "son cümleyi sil" can take it back) and
/// where. Typing stops when another app comes to the front.
@MainActor
final class DictationSession {
    /// How long dictation waits for the next sentence before it ends.
    static let window: TimeInterval = 60
    private static let maxRemembered = 50
    private enum Key {
        static let returnKey: CGKeyCode = 36
        static let delete: CGKeyCode = 51
    }

    private(set) var isActive = false
    private var target: NSRunningApplication?
    private var typed: [String] = []

    func begin(in app: NSRunningApplication) {
        isActive = true
        target = app
        typed = []
    }

    func end() {
        isActive = false
        target = nil
        typed = []
    }

    /// One dictated utterance: a control ("yeni satır", "son cümleyi sil", "dikteyi bitir") or text.
    /// Returns what to say, usually nothing.
    func handle(_ input: String) async -> String {
        guard isActive, let target else { return "" }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            end()
            return "Öndeki uygulama değişti, dikteyi bitirdim."
        }
        do {
            switch DictationCommand.parse(input) {
            case .finish:
                end()
                return "Dikte bitti."
            case .newLine:
                try newLine()
            case .newParagraph:
                try newLine()
                try newLine()
            case .deleteLast:
                guard let last = typed.popLast() else { return "Silinecek bir şey yok." }
                for _ in 0..<last.count { try AccessibilityControl.press(Key.delete) }
            case nil:
                let text = TypedText.sanitized(DictationText.format(input, after: typed.joined()))
                guard !text.isEmpty else { return "" }
                try await AccessibilityControl.type(text, into: target.processIdentifier)
                remember(text)
            }
            return ""
        } catch {
            end()
            return ToolReply.spoken(ToolReply.failure(error))
        }
    }

    /// Shift-Return: a line break everywhere, where plain Return would send a message in Messages.
    private func newLine() throws {
        try AccessibilityControl.press(Key.returnKey, flags: .maskShift)
        remember("\n")
    }

    private func remember(_ text: String) {
        typed = Array((typed + [text]).suffix(Self.maxRemembered))
    }
}
