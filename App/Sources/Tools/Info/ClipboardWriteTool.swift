import AppKit
import FoundationModels

/// What the assistant last said, so "bunu panoya kopyala" can refer to it.
@MainActor
final class ConversationContext {
    var lastReply: String?
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
            return ToolReply.failure("Panoya ne kopyalayacağımı anlayamadım.")
        }
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        return "Panoya kopyaladım."
    }
}
