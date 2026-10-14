import AppKit
import AsistanCore
import FoundationModels
import UniformTypeIdentifiers

/// "Bunu özetle", "bu sayfayı çevir", "şu dosyayı aç": acts on what the user points at on screen
/// (see `ContextResolver`). Text that is read is untrusted and answered by the tool-less session.
struct ContextTool: AssistantTool {
    let name = "useContext"
    let description = "Ekranda seçili metni, Finder'da seçili dosyayı, tarayıcıdaki sayfayı ya da açık belgeyi özetler, çevirir, açıklar, okur ya da açar ('bunu özetle', 'şu dosyayı aç')."
    let context: ConversationContext
    private static let maxCharacters = 6000
    private static let maxOpenedFiles = 5

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var command: String
    }

    /// Taken by rule when the command points at something and that something is on screen; otherwise
    /// the command is routed as before (a screen reading, for instance).
    @MainActor
    func claims(_ command: String) -> Bool {
        guard let intent = ContextIntent.parse(command), let screen = context.screen else { return false }
        return ContextResolver.resolve(intent.wanted, in: screen) != nil
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(command: command)
    }

    func call(arguments: Arguments) async throws -> String {
        try await makeCall(arguments).execute()
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let screen = await MainActor.run { context.screen }
        guard let intent = ContextIntent.parse(arguments.command), let screen,
              let item = ContextResolver.resolve(intent.wanted, in: screen) else {
            return .unavailable(name, message: "Neyi kastettiğini bulamadım. Bir metni seç, dosyayı Finder'da işaretle ya da sayfayı aç.")
        }
        if intent.action == .open {
            return PreparedToolCall(toolName: name, argumentsDescription: "open", risk: .safe, confirmationQuestion: nil,
                                    execute: { await Self.open(item) })
        }
        return PreparedToolCall(toolName: name, argumentsDescription: "read", risk: .safe, confirmationQuestion: nil,
                                answersWithLanguageModel: true, execute: { try await Self.material(item) })
    }

    private static func material(_ item: ContextItem) async throws -> String {
        switch item {
        case let .text(text):
            return String(text.prefix(maxCharacters))
        case let .page(url, _):
            return try await BrowserPage.text(of: url)
        case let .document(url):
            return try document(url)
        case let .files(urls):
            guard let readable = urls.first(where: { ReadDocumentTool.readableExtensions.contains($0.pathExtension.lowercased()) }) else {
                return ToolReply.failure("Seçili dosyalardan okuyabileceğim bir belge yok.")
            }
            return try document(readable)
        }
    }

    private static func document(_ url: URL) throws -> String {
        let text = try ReadDocumentTool.text(of: url).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ToolReply.failure("'\(url.lastPathComponent)' içinde okunabilir yazı yok.") }
        return "Belge: \(url.lastPathComponent)\n\(text.prefix(maxCharacters))"
    }

    /// Opens documents and pages; never apps, scripts or other programs, which opening would run.
    @MainActor
    private static func open(_ item: ContextItem) -> String {
        let urls: [URL] = switch item {
        case let .files(files): Array(files.prefix(maxOpenedFiles))
        case let .document(url): [url]
        case let .page(url, _): [url]
        case .text: []
        }
        guard !urls.isEmpty else { return ToolReply.failure("Seçili metin açılacak bir şey değil.") }
        if let program = urls.first(where: isProgram) {
            return ToolReply.failure("Güvenlik için '\(program.lastPathComponent)' gibi programları sesle açmıyorum.")
        }
        urls.forEach { NSWorkspace.shared.open($0) }
        return urls.count == 1 ? "\(urls[0].lastPathComponent) açılıyor." : "\(urls.count) dosya açılıyor."
    }

    private static func isProgram(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return true }
        return [.executable, .application, .applicationBundle, .script, .shellScript, .unixExecutable]
            .contains { type.conforms(to: $0) } || ["command", "tool", "workflow", "terminal", "pkg", "mpkg"].contains(url.pathExtension.lowercased())
    }
}
