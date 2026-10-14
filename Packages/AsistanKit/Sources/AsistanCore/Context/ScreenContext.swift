import Foundation

/// What the user may be pointing at when they say "bu" or "şu": captured when the command is heard.
public struct ScreenContext: Equatable, Sendable {
    public var selectedText: String?
    public var selectedFiles: [URL]
    public var pageURL: URL?
    public var pageTitle: String?
    /// The file shown in the front window (Preview, TextEdit, Word…).
    public var documentURL: URL?

    public init(selectedText: String? = nil, selectedFiles: [URL] = [], pageURL: URL? = nil, pageTitle: String? = nil,
                documentURL: URL? = nil) {
        self.selectedText = selectedText
        self.selectedFiles = selectedFiles
        self.pageURL = pageURL
        self.pageTitle = pageTitle
        self.documentURL = documentURL
    }
}

public enum ContextItem: Equatable, Sendable {
    case text(String)
    case files([URL])
    case page(URL, title: String?)
    case document(URL)
}

public enum ContextResolver {
    /// The named kind when the user said one ("bu dosya", "bu sayfa"); otherwise the most specific
    /// thing on screen: a selection, then selected files, then the page, then the open document.
    public static func resolve(_ wanted: ContextIntent.Kind?, in screen: ScreenContext) -> ContextItem? {
        let text = screen.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank.map(ContextItem.text)
        let files = screen.selectedFiles.isEmpty ? nil : ContextItem.files(screen.selectedFiles)
        let page = screen.pageURL.map { ContextItem.page($0, title: screen.pageTitle) }
        let document = screen.documentURL.map(ContextItem.document)
        switch wanted {
        case .text: return text
        case .page: return page
        case .file: return files ?? screen.documentURL.map { .files([$0]) }
        case .document: return document ?? files
        case nil: return text ?? files ?? page ?? document
        }
    }
}

private extension String {
    var nilIfBlank: String? { isEmpty ? nil : self }
}
