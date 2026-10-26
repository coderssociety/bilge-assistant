import AsistanCore
import Foundation
import FoundationModels

/// "Alışveriş notumda ne yazıyor?", "son notumu oku". Notes can hold text clipped from the web or a mail, so their
/// text and titles are untrusted: answered by the tool-less session like screen text, and marking a multi-step plan
/// as having read outside content. "Notlarım neler" lists the latest titles instead.
struct ReadNotesTool: AssistantTool {
    let name = "readNotes"
    let description = "Notlar uygulamasında bir notu arar ve içeriğini okur; konu söylenmezse en son notu okur. Notların listesini de söyler."
    let answersWithLanguageModel = true
    let readingLayout: ContinuedReading.Layout? = .text(maxCharacters: 3000)
    private static let listedNotes = 30
    private static let listLayout = ContinuedReading.Layout.list(separator: "; ", perPart: 10)

    @Generable
    struct Arguments {
        @Guide(description: "Aranan notun konusu ya da içindeki bir kelime; en son not isteniyorsa boş bırak")
        var query: String?
        @Guide(description: "Notların listesi isteniyorsa true")
        var list: Bool
    }

    /// Whether to list is read from the words alone ("notlarım neler"), never guessed.
    func arguments(fromCommand command: String) -> Arguments? {
        NoteRequest.asksForList(command, language: AppLanguage.current) ? Arguments(query: nil, list: true) : nil
    }

    func refine(_ arguments: Arguments, command: String) -> Arguments {
        Arguments(query: arguments.query, list: false)
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        guard arguments.list else {
            return PreparedToolCall(toolName: name, argumentsDescription: String(describing: arguments), risk: risk,
                                    confirmationQuestion: nil, answersWithLanguageModel: answersWithLanguageModel,
                                    readingLayout: readingLayout, execute: { try await call(arguments: arguments) })
        }
        return PreparedToolCall(toolName: name, argumentsDescription: "list", risk: risk, confirmationQuestion: nil,
                                readingLayout: Self.listLayout, execute: { await Self.listNotes() })
    }

    private static func listNotes() async -> String {
        do {
            let entries = try await NotesLibrary.index()
            let recent = NoteIndex.recent(entries, limit: listedNotes)
            guard !recent.isEmpty else { return ToolReply.failure(String(localized: "Hiç not bulamadım.")) }
            return String(localized: "\(entries.count) notun var, en son düzenlenenler: \(recent.map(\.name).joined(separator: "; "))")
        } catch {
            return ToolReply.failure(error)
        }
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.query?.trimmingCharacters(in: .whitespaces) ?? ""
        let selection = query.isEmpty
            ? "set found to notes"
            : """
            set found to (notes whose name contains \(AppleScriptRunner.quoted(query)))
            if (count of found) = 0 then set found to (notes whose plaintext contains \(AppleScriptRunner.quoted(query)))
            """
        do {
            let text = try await AppleScriptRunner.run("""
            tell application "Notes"
            \(selection)
            if (count of found) = 0 then return ""
            set picked to item 1 of found
            return (name of picked) & linefeed & (plaintext of picked)
            end tell
            """)
            guard !text.isEmpty else {
                return ToolReply.failure(query.isEmpty
                    ? String(localized: "Hiç not bulamadım.")
                    : String(localized: "'\(query)' geçen bir not bulamadım."))
            }
            return text
        } catch {
            return ToolReply.failure(error)
        }
    }
}
