import Foundation
import FoundationModels

/// Moves one file to the Trash after naming it out loud. Never deletes permanently.
struct TrashFileTool: AssistantTool {
    let name = "moveFileToTrash"
    let description = "Adı söylenen bir dosyayı Çöp Kutusu'na taşır (kalıcı silmez)."
    let risk = ToolRisk.needsConfirmation

    @Generable
    struct Arguments {
        @Guide(description: "Dosya adında geçen kelimeler, örn. 'eski fatura'")
        var query: String
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let match: URL?
        do {
            match = try await FileSearch.find(arguments.query, limit: 1).first
        } catch {
            return .unavailable(name, message: error.localizedDescription)
        }
        guard let file = match else {
            return .unavailable(name, message: "'\(arguments.query)' ile eşleşen dosya bulunamadı.")
        }
        let location = FileSearch.describeLocation(file)
        return PreparedToolCall(
            toolName: name,
            argumentsDescription: file.path,
            risk: risk,
            confirmationQuestion: "\(location) içindeki '\(file.lastPathComponent)' dosyasını çöp kutusuna taşıyayım mı?",
            execute: { Self.trash(file) })
    }

    /// Only the confirmed path from `makeCall` may trash a file; a direct call never does.
    func call(arguments: Arguments) async throws -> String {
        ToolReply.failure("Dosya silme yalnızca sesli onayla yapılabilir.")
    }

    private static func trash(_ file: URL) -> String {
        do {
            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
            return "'\(file.lastPathComponent)' çöp kutusuna taşındı. Gerekirse oradan geri alabilirsin."
        } catch {
            return ToolReply.failure(error)
        }
    }
}
