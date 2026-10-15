import Foundation
import FoundationModels

struct CreateNoteTool: AssistantTool {
    let name = "createNote"
    let description = "Notlar uygulamasında yeni bir not oluşturur."

    @Generable
    struct Arguments {
        @Guide(description: "Notun kısa başlığı")
        var title: String
        @Guide(description: "Notun içeriği; yoksa boş bırak")
        var body: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let html = Self.html(title: arguments.title, body: arguments.body ?? "")
        do {
            _ = try await AppleScriptRunner.run("""
            tell application "Notes"
            make new note at default account with properties {body:\(AppleScriptRunner.quoted(html))}
            end tell
            """)
            return String(localized: "'\(arguments.title)' başlıklı not oluşturuldu.")
        } catch {
            return ToolReply.failure(error)
        }
    }

    /// Notes stores HTML; escape the text so it is shown literally.
    private static func html(title: String, body: String) -> String {
        "<h1>\(escape(title))</h1>" + (body.isEmpty ? "" : "<div>\(escape(body))</div>")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
