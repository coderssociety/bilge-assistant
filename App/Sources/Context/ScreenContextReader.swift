import AppKit
import AsistanCore

/// Reads what is on screen when a command points at something ("bunu Ahmet'e gönder"): the selection
/// in the front app, files selected in Finder, the browser page, the document in the front window.
/// Nothing is read for other commands.
@MainActor
enum ScreenContextReader {
    private static let maxFiles = 20
    private static let finderIdentifier = "com.apple.finder"

    static func snapshot() async -> ScreenContext {
        var screen = ScreenContext()
        guard let front = AccessibilityControl.frontApplication() else { return screen }
        screen.selectedText = (try? AccessibilityControl.selectedText()) ?? nil
        screen.documentURL = frontDocument()
        if front.bundleIdentifier == finderIdentifier {
            screen.selectedFiles = await finderSelection()
        } else if BrowserPage.isBrowser(front.bundleIdentifier), let page = try? await BrowserPage.current(frontmostOnly: true) {
            screen.pageURL = page.url
            screen.pageTitle = page.title
        }
        return screen
    }

    /// Document-based apps (Preview, TextEdit, Pages, Word) expose the window's file as AXDocument.
    private static func frontDocument() -> URL? {
        guard let window = try? AccessibilityControl.focusedWindow(),
              let path = AccessibilityControl.attribute(window, kAXDocumentAttribute) as? String,
              let url = URL(string: path), url.isFileURL
        else { return nil }
        return url
    }

    private static func finderSelection() async -> [URL] {
        let output = try? await AppleScriptRunner.run("""
        tell application "Finder"
        set out to {}
        repeat with selectedItem in (get selection)
            set end of out to POSIX path of (selectedItem as alias)
        end repeat
        set AppleScript's text item delimiters to linefeed
        return out as text
        end tell
        """)
        return (output ?? "").split(separator: "\n").prefix(maxFiles).map { URL(filePath: String($0)) }
    }
}
