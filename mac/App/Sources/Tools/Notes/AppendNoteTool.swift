import AsistanCore
import Foundation
import FoundationModels

/// "Alışveriş notuma süt ekle": adds the user's own words to the end of an existing note. The note is found
/// before asking, so the question names the note that will change.
struct AppendNoteTool: AssistantTool {
    let name = "appendToNote"
    let description = "Notlar'daki mevcut bir notun sonuna metin ekler ('alışveriş notuma süt ekle')."
    let risk = ToolRisk.needsConfirmation

    @Generable
    struct Arguments {
        @Guide(description: "Notun eksiz adı: 'alışveriş notuma' → 'alışveriş'")
        var note: String
        @Guide(description: "Eklenecek metin, kullanıcının söylediği gibi")
        var text: String
    }

    func arguments(fromCommand command: String) -> Arguments? {
        NoteRequest.addition(in: command, language: AppLanguage.current).map { Arguments(note: $0.note, text: $0.text) }
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let text = arguments.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .unavailable(name, message: String(localized: "Nota ne eklememi istediğini anlayamadım."))
        }
        let note: NoteIndex.Entry?
        do {
            note = NoteIndex.find(arguments.note, in: try await NotesLibrary.index())
        } catch {
            return .unavailable(name, message: error.localizedDescription)
        }
        guard let note else {
            return .unavailable(name, message: String(localized: "'\(arguments.note)' adında bir not bulamadım."))
        }
        return PreparedToolCall(
            toolName: name,
            argumentsDescription: "note: \(note.id)",
            risk: risk,
            confirmationQuestion: String(localized: "'\(note.name)' notunun sonuna şunu ekleyeyim mi: \(Recipient.preview(text))"),
            execute: { await Self.append(text, to: note) })
    }

    func call(arguments: Arguments) async throws -> String {
        ToolReply.failure(String(localized: "Nota yalnızca onayla eklerim."))
    }

    private static func append(_ text: String, to note: NoteIndex.Entry) async -> String {
        do {
            switch try await NotesLibrary.append(text, toNoteWithID: note.id) {
            case .appended?:
                return String(localized: "'\(note.name)' notuna ekledim.")
            case .locked?:
                return ToolReply.failure(String(localized: "'\(note.name)' notu kilitli, ona ekleyemem."))
            case .hasAttachments?:
                return ToolReply.failure(String(localized: "'\(note.name)' notunda ekler var; bozulmasın diye ona yazmadım."))
            case nil:
                return ToolReply.failure(String(localized: "Notlar'dan beklenmedik bir yanıt geldi; notu kontrol etmen iyi olur."))
            }
        } catch {
            return ToolReply.failure(error)
        }
    }
}
