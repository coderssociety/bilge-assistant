import AppKit
import AsistanCore

/// The page open in Safari, Chrome, Edge, Brave or Arc, and its readable text.
enum BrowserPage {
    private struct Scripts {
        let url: String
        let title: String
    }

    private static let browsers: [String: Scripts] = [
        "com.apple.Safari": Scripts(url: "tell application \"Safari\" to return URL of front document",
                                    title: "tell application \"Safari\" to return name of front document"),
        "com.google.Chrome": chromium("Google Chrome"),
        "com.microsoft.edgemac": chromium("Microsoft Edge"),
        "com.brave.Browser": chromium("Brave Browser"),
        "company.thebrowser.Browser": chromium("Arc"),
    ]
    private static let maxCharacters = 6000

    static func isBrowser(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map { browsers[$0] != nil } ?? false
    }

    /// The frontmost browser's page; with `frontmostOnly` false, also a browser in the background.
    static func current(frontmostOnly: Bool) async throws -> (url: URL, title: String?)? {
        let candidates = await MainActor.run {
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let running = frontmostOnly ? [] : NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            return ([front].compactMap { $0 } + running).filter { browsers[$0] != nil }
        }
        guard let browser = candidates.first, let scripts = browsers[browser],
              let url = URL(string: try await AppleScriptRunner.run(scripts.url)), url.scheme != nil
        else { return nil }
        let title = (try? await AppleScriptRunner.run(scripts.title))?.nilIfEmpty
        return (url, title)
    }

    /// The page fetched again and reduced to its text. It is untrusted: answer from it in a tool-less session.
    static func text(of url: URL) async throws -> String {
        let html = try await WebFetch.text(from: url)
        let text = HTMLText.extract(html)
        guard !text.isEmpty else { return ToolReply.failure("Sayfada okunabilir yazı yok.") }
        let title = HTMLText.title(html).map { "Başlık: \($0)\n" } ?? ""
        return title + String(text.prefix(maxCharacters))
    }

    private static func chromium(_ name: String) -> Scripts {
        Scripts(url: "tell application \"\(name)\" to return URL of active tab of front window",
                title: "tell application \"\(name)\" to return title of active tab of front window")
    }
}
