import AsistanCore
import Foundation
import FoundationModels

/// "Alışveriş notumda ne yazıyor?", "son notumu oku". Note text is user content, but it is still
/// answered by the tool-less session, like screen text.
struct ReadNotesTool: AssistantTool {
    let name = "readNotes"
    let description = "Notlar uygulamasında bir notu arar ve içeriğini okur; konu söylenmezse en son notu okur."
    let answersWithLanguageModel = true
    let readingLayout: ContinuedReading.Layout? = .text(maxCharacters: 3000)

    @Generable
    struct Arguments {
        @Guide(description: "Aranan notun konusu ya da içindeki bir kelime; en son not isteniyorsa boş bırak")
        var query: String?
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
