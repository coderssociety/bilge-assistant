import AppKit
import AsistanCore
import Foundation
import FoundationModels

/// "Claude'un keşfettiği buluşu aç", "üçüncü haberi anlat": one of the headlines just read, fetched and told in
/// short; "aç" also shows it in the browser. Routed by rule, since the router model takes such requests for the
/// news itself. The article is untrusted and only answered by the tool-less session.
struct NewsArticleTool: RuleRoutedTool {
    let name = "newsArticle"
    let description = "Az önce okunan haber başlıklarından birini açar ve ne anlattığını söyler."
    let answersWithLanguageModel = true
    let reading: NewsReading

    @Generable
    struct Arguments {
        var title: String
        var link: String
        var inBrowser: Bool
    }

    @MainActor
    func claims(_ command: String) -> Bool {
        reading.article(for: command)?.item.link != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        guard let found = reading.article(for: command), let link = found.item.link else { return nil }
        return Arguments(title: found.item.title, link: link.absoluteString, inBrowser: found.inBrowser)
    }

    func call(arguments: Arguments) async throws -> String {
        guard let url = URL(string: arguments.link), reading.wasRead(url) else {
            return ToolReply.failure(String(localized: "Hangi haberi açacağımı bulamadım; okuduğum başlıklardan birini söyler misin?"))
        }
        if arguments.inBrowser {
            _ = await MainActor.run { NSWorkspace.shared.open(url) }
        }
        do {
            let page = try await BrowserPage.text(of: url)
            guard !ToolReply.isFailure(page) else { return Self.openedOnly(arguments) ?? page }
            let opened = arguments.inBrowser ? String(localized: "(Haber tarayıcıda açıldı.)\n") : ""
            return String(localized: "Haber: \(arguments.title)\n") + opened + page
        } catch {
            return Self.openedOnly(arguments) ?? ToolReply.failure(error)
        }
    }

    /// The page could not be read here, but it is open in the browser.
    private static func openedOnly(_ arguments: Arguments) -> String? {
        arguments.inBrowser ? String(localized: "Haberi tarayıcıda açtım: \(arguments.title)") : nil
    }
}
