import AppKit
import AsistanCore
import FoundationModels

/// "Annemi ara", "Ahmet'i FaceTime'la ara". A phone call opens a tel: URL, which macOS places through the
/// iPhone (Continuity calling); FaceTime takes facetime-audio:// or facetime://. The person is looked up
/// first, so the question names who and which number will be called.
struct CallContactTool: AssistantTool {
    let name = "callContact"
    let description = "Kişiler'deki birini telefonla (iPhone üzerinden) ya da FaceTime ile arar ('annemi ara', 'Ahmet'i FaceTime'la ara')."
    let risk = ToolRisk.needsConfirmation

    @Generable
    enum Mode {
        case phone, faceTimeAudio, faceTimeVideo
    }

    @Generable
    struct Arguments {
        @Guide(description: "Aranacak kişinin eksiz adı: 'Ahmet'i' → 'Ahmet', 'annemi' → 'annem'")
        var name: String
        @Guide(description: "FaceTime ya da sesli denirse faceTimeAudio, görüntülü denirse faceTimeVideo, yoksa phone")
        var mode: Mode
        @Guide(description: "Bu alan kullanılmaz; false")
        var searchesIfUnknown: Bool
    }

    func arguments(fromCommand command: String) -> Arguments? {
        CallRequest.parse(command, language: AppLanguage.current).map(Self.arguments(for:))
    }

    /// Only a bare "<Ad>'ı ara" may have been a web search; the model never decides that.
    func refine(_ arguments: Arguments, command: String) -> Arguments {
        Arguments(name: arguments.name, mode: arguments.mode, searchesIfUnknown: false)
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let spoken = arguments.name.trimmingCharacters(in: .whitespaces)
        let mode = Self.mode(arguments.mode)
        let person: (name: String, phones: [String], emails: [String])
        if PhoneNumber.normalized(spoken) != nil {
            person = (spoken, [spoken], [])
        } else {
            let contact: ContactSummary?
            do {
                contact = try await ContactsAccess.shared.find(spoken)
            } catch {
                return .unavailable(name, message: error.localizedDescription)
            }
            guard let contact else {
                if arguments.searchesIfUnknown {
                    return await WebSearchTool().makeCall(WebSearchTool.Arguments(query: spoken, service: .google))
                }
                return .unavailable(name, message: String(localized: "Kişilerinde '\(spoken)' adında birini bulamadım."))
            }
            person = (contact.name, contact.phones, contact.emails)
        }
        guard let destination = CallRequest.destination(for: mode, phones: person.phones, emails: person.emails) else {
            return .unavailable(name, message: mode == .phone
                ? String(localized: "\(person.name) için kayıtlı bir telefon numarası yok.")
                : String(localized: "\(person.name) için FaceTime'da aranabilecek bir numara ya da e-posta yok."))
        }
        return PreparedToolCall(
            toolName: name,
            argumentsDescription: "mode: \(mode)",
            risk: risk,
            confirmationQuestion: Self.question(name: person.name, address: destination.address, mode: mode),
            execute: { await Self.place(destination.url, calling: person.name) })
    }

    func call(arguments: Arguments) async throws -> String {
        ToolReply.failure(String(localized: "Aramayı yalnızca onayla başlatırım."))
    }

    private static func arguments(for request: CallRequest) -> Arguments {
        let mode: Mode = switch request.mode {
        case .phone: .phone
        case .faceTimeAudio: .faceTimeAudio
        case .faceTimeVideo: .faceTimeVideo
        }
        return Arguments(name: request.name, mode: mode, searchesIfUnknown: !request.isCertain)
    }

    private static func mode(_ mode: Mode) -> CallRequest.Mode {
        switch mode {
        case .phone: .phone
        case .faceTimeAudio: .faceTimeAudio
        case .faceTimeVideo: .faceTimeVideo
        }
    }

    private static func question(name: String, address: String, mode: CallRequest.Mode) -> String {
        switch mode {
        case .phone: String(localized: "\(name), \(address) numarasını iPhone üzerinden arayayım mı?")
        case .faceTimeAudio: String(localized: "\(name), \(address) adresini FaceTime sesli aramayla arayayım mı?")
        case .faceTimeVideo: String(localized: "\(name), \(address) adresini FaceTime görüntülü aramayla arayayım mı?")
        }
    }

    /// macOS may still show its own call button before dialling.
    private static func place(_ url: URL, calling name: String) async -> String {
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        return opened
            ? String(localized: "\(name) aranıyor.")
            : ToolReply.failure(String(localized: "Arama başlatılamadı. FaceTime'ın ve iPhone'dan arama ayarının açık olduğunu kontrol et."))
    }
}
