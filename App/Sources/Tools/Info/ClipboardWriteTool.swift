import AsistanCore
import AppKit
import FoundationModels

/// What the assistant last said, so "bunu panoya kopyala" can refer to it.
@MainActor
final class ConversationContext {
    var lastReply: String?
    /// What was on screen when the current command was heard, read only for commands that point ("bunu").
    var screen: ScreenContext?
    /// What the last tool read, in parts, for "devamını oku" and questions about it.
    var reading: ContinuedReading?
}

struct CopyToClipboardTool: AssistantTool {
    let name = "copyToClipboard"
    let description = "Söylenen metni ya da az önceki yanıtı panoya kopyalar ('bunu kopyala', 'şunu panoya al: ...')."
    let context: ConversationContext

    @Generable
    struct Arguments {
        @Guide(description: "Kopyalanacak metin; 'bunu', 'az önceki yanıtı' deniyorsa boş bırak")
        var text: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let given = arguments.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = await MainActor.run { context.lastReply }
        guard let text = given.isEmpty ? fallback : given, !text.isEmpty else {
            return ToolReply.failure(String(localized: "Panoya ne kopyalayacağımı anlayamadım."))
        }
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        return String(localized: "Panoya kopyaladım.")
    }
}
