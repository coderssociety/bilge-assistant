import AsistanCore
import FoundationModels

/// "Eşimin adının Ayşe olduğunu hatırla". The fact is taken from the command as spoken, so nothing
/// is invented. "Bunu hatırla" refers to the assistant's previous reply, which may echo a web page or
/// an e-mail, so that is read back and stored only after a yes.
struct RememberTool: AssistantTool {
    let name = "remember"
    let description = "Kullanıcının hatırlamanı istediği bir bilgiyi kalıcı olarak kaydeder ('…olduğunu hatırla', 'unutma', 'aklında tut')."
    let memory: MemoryStore
    let context: ConversationContext

    @Generable
    struct Arguments {
        @Guide(description: "Hatırlanacak bilgi, kullanıcının cümlesiyle; 'bunu hatırla' deniyorsa boş bırak")
        var fact: String?
    }

    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(fact: MemoryIntent.fact(from: command))
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let given = arguments.fact?.trimmingCharacters(in: .whitespaces) ?? ""
        if !given.isEmpty {
            return PreparedToolCall(toolName: name, argumentsDescription: "fact", risk: .safe, confirmationQuestion: nil,
                                    execute: { await store(given) })
        }
        guard let previous = await MainActor.run(body: { context.lastReply }), !previous.isEmpty else {
            return .unavailable(name, message: "Neyi hatırlamamı istediğini anlayamadım.")
        }
        let fact = String(previous.prefix(MemoryBook.maxEntryLength))
        return PreparedToolCall(toolName: name, argumentsDescription: "previous reply", risk: .needsConfirmation,
                                confirmationQuestion: "Şunu hatırlayayım mı: \(fact)",
                                execute: { await store(fact) })
    }

    func call(arguments: Arguments) async throws -> String {
        try await makeCall(arguments).execute()
    }

    private func store(_ fact: String) async -> String {
        do {
            let outcome = try await MainActor.run { try memory.remember(fact) }
            return switch outcome {
            case .added: "Tamam, hatırlayacağım."
            case .addedDroppingOldest: "Tamam, hatırlayacağım. Yer açmak için en eski bilgiyi unuttum."
            case .duplicate: "Bunu zaten biliyorum."
            case .rejected: ToolReply.failure("Bu hatırlamak için fazla uzun, daha kısa söyler misin?")
            }
        } catch {
            return ToolReply.failure(error)
        }
    }
}

/// "Kahveyle ilgili bilgiyi unut", "bunu unut" (the latest fact), "her şeyi unut". The fact is found
/// first and named in the question, so a loose match never deletes the wrong one unnoticed.
struct ForgetTool: AssistantTool {
    let name = "forget"
    let description = "Hafızaya kaydedilmiş bir bilgiyi ya da tüm hafızayı siler ('…unut', 'hafızanı temizle')."
    let memory: MemoryStore

    @Generable
    struct Arguments {
        @Guide(description: "Silinecek bilgiyi anlatan sözcükler; 'bunu unut' için boş bırak")
        var about: String?
        @Guide(description: "Her şey silinecekse true")
        var everything: Bool
    }

    func arguments(fromCommand command: String) -> Arguments? {
        switch MemoryIntent.forgetTarget(from: command) {
        case .all: Arguments(about: nil, everything: true)
        case .latest: Arguments(about: nil, everything: false)
        case let .matching(query): Arguments(about: query, everything: false)
        }
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        if arguments.everything {
            let count = await MainActor.run { memory.book.entries.count }
            guard count > 0 else { return .unavailable(name, message: "Hafızamda zaten bir şey yok.") }
            return PreparedToolCall(toolName: name, argumentsDescription: "everything", risk: .needsConfirmation,
                                    confirmationQuestion: "Hatırladığım \(count) bilginin hepsini sileyim mi?",
                                    execute: { await forgetAll() })
        }
        let about = arguments.about?.trimmingCharacters(in: .whitespaces) ?? ""
        let entry = await MainActor.run { about.isEmpty ? memory.book.latest : memory.entry(matching: about) }
        guard let entry else {
            return .unavailable(name, message: about.isEmpty ? "Hafızamda bir şey yok." : "Hafızamda '\(about)' ile ilgili bir bilgi bulamadım.")
        }
        return PreparedToolCall(toolName: name, argumentsDescription: "one fact", risk: .needsConfirmation,
                                confirmationQuestion: "'\(entry.text)' bilgisini unutayım mı?",
                                execute: { await forget(entry) })
    }

    func call(arguments: Arguments) async throws -> String {
        try await makeCall(arguments).execute()
    }

    private func forget(_ entry: MemoryEntry) async -> String {
        do {
            try await MainActor.run { try memory.forget(id: entry.id) }
            return "Unuttum: \(entry.text)."
        } catch {
            return ToolReply.failure(error)
        }
    }

    private func forgetAll() async -> String {
        do {
            let count = try await MainActor.run { try memory.forgetAll() }
            return "Hafızamı temizledim, \(count) bilgiyi sildim."
        } catch {
            return ToolReply.failure(error)
        }
    }
}

/// "Benim hakkımda ne biliyorsun", "neleri hatırlıyorsun".
struct ListMemoriesTool: AssistantTool {
    let name = "listMemories"
    let description = "Hafızaya kaydedilmiş bilgileri okur ('benim hakkımda ne biliyorsun', 'neleri hatırlıyorsun')."
    let memory: MemoryStore
    private static let spokenCount = 8

    @Generable
    struct Arguments {}

    func emptyArguments() -> Arguments? { Arguments() }

    func call(arguments: Arguments) async throws -> String {
        let entries = await MainActor.run { memory.book.entries }
        guard !entries.isEmpty else { return "Henüz hatırlamamı istediğin bir şey yok." }
        let newest = entries.suffix(Self.spokenCount).reversed().map(\.text)
        let rest = entries.count - newest.count
        let more = rest > 0 ? " Bunlar en yenileri, \(rest) bilgi daha var." : ""
        return "Bana şunları söylemiştin: \(newest.joined(separator: "; "))." + more
    }
}
