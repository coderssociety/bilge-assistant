import AppKit
import AsistanCore

/// The page open in Safari, Chrome, Edge, Brave or Arc, and its readable text.
enum BrowserPage {
    private struct Browser {
        let name: String
        let isSafari: Bool
    }

    /// Browsers whose tabs and pages AppleScript can read and switch.
    private static let scriptable: [String: Browser] = [
        "com.apple.Safari": Browser(name: "Safari", isSafari: true),
        "com.google.Chrome": Browser(name: "Google Chrome", isSafari: false),
        "com.microsoft.edgemac": Browser(name: "Microsoft Edge", isSafari: false),
        "com.brave.Browser": Browser(name: "Brave Browser", isSafari: false),
        "company.thebrowser.Browser": Browser(name: "Arc", isSafari: false),
    ]
    /// Also reachable by keyboard shortcuts, though not by AppleScript.
    private static let keyboardOnly: Set<String> = ["org.mozilla.firefox"]
    private static let maxCharacters = 6000

    static func isBrowser(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map { scriptable[$0] != nil || keyboardOnly.contains($0) } ?? false
    }

    static func isScriptable(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map { scriptable[$0] != nil } ?? false
    }

    /// The frontmost browser's page; with `frontmostOnly` false, also a browser in the background.
    static func current(frontmostOnly: Bool) async throws -> (url: URL, title: String?)? {
        let candidates = await MainActor.run {
            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let running = frontmostOnly ? [] : NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            return ([front].compactMap { $0 } + running).filter { scriptable[$0] != nil }
        }
        guard let identifier = candidates.first, let browser = scriptable[identifier],
              let url = URL(string: try await AppleScriptRunner.run(script(browser, "URL"))), url.scheme != nil
        else { return nil }
        let title = (try? await AppleScriptRunner.run(script(browser, browser.isSafari ? "name" : "title")))?.nilIfEmpty
        return (url, title)
    }

    /// The page fetched again and reduced to its text. It is untrusted: answer from it in a tool-less session.
    static func text(of url: URL) async throws -> String {
        let html = try await WebFetch.text(from: url)
        let text = HTMLText.extract(html)
        guard !text.isEmpty else { return ToolReply.failure(String(localized: "Sayfada okunabilir yazı yok.")) }
        let title = HTMLText.title(html).map { "Başlık: \($0)\n" } ?? ""
        return title + String(text.prefix(maxCharacters))
    }

    static func tabTitles(in bundleIdentifier: String) async throws -> [String] {
        guard let browser = scriptable[bundleIdentifier] else { return [] }
        let property = browser.isSafari ? "name" : "title"
        let output = try await AppleScriptRunner.run("""
        tell application \(AppleScriptRunner.quoted(browser.name))
        set AppleScript's text item delimiters to linefeed
        return (\(property) of every tab of front window) as text
        end tell
        """)
        return output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Brings the front window's tab `index` (from 1) forward.
    static func selectTab(_ index: Int, in bundleIdentifier: String) async throws {
        guard let browser = scriptable[bundleIdentifier] else { return }
        let command = browser.isSafari
            ? "set current tab of front window to tab \(index) of front window"
            : "set active tab index of front window to \(index)"
        _ = try await AppleScriptRunner.run("tell application \(AppleScriptRunner.quoted(browser.name)) to \(command)")
    }

    /// The URL or title of the page in front.
    private static func script(_ browser: Browser, _ property: String) -> String {
        let page = browser.isSafari ? "front document" : "active tab of front window"
        return "tell application \(AppleScriptRunner.quoted(browser.name)) to return \(property) of \(page)"
    }
}
