import AsistanCore
import Foundation
import FoundationModels

/// Who a message goes to, resolved before the user is asked, so the question names the exact address.
struct Recipient: Sendable {
    let name: String
    let address: String

    enum Kind { case email, phone }

    private static let previewCharacters = 300

    /// The question reads the text aloud; a long body is cut so it stays listenable.
    static func preview(_ text: String) -> String {
        text.count <= previewCharacters ? text : String(text.prefix(previewCharacters)) + "… (devamı var)."
    }

    static func resolve(_ spoken: String, as kind: Kind) async throws -> Recipient? {
        let trimmed = spoken.trimmingCharacters(in: .whitespaces)
        if kind == .email, trimmed.contains("@"), !trimmed.contains(" ") { return Recipient(name: trimmed, address: trimmed) }
        if kind == .phone, let number = PhoneNumber.normalized(trimmed) { return Recipient(name: trimmed, address: number) }
        guard let contact = try await ContactsAccess.shared.find(trimmed) else { return nil }
        switch kind {
        case .email:
            return contact.emails.first.map { Recipient(name: contact.name, address: $0) }
        case .phone:
            if let phone = contact.phones.lazy.compactMap({ PhoneNumber.normalized($0) }).first {
                return Recipient(name: contact.name, address: phone)
            }
            return contact.emails.first.map { Recipient(name: contact.name, address: $0) }
        }
    }
}

struct SendEmailTool: AssistantTool {
    let name = "sendEmail"
    let description = "Mail uygulamasıyla birine e-posta gönderir; göndermeden önce kime ne gideceğini okuyup onay ister."
    let risk = ToolRisk.needsConfirmation

    @Generable
    struct Arguments {
        @Guide(description: "Alıcının eksiz adı ya da e-posta adresi: 'Ahmet'e' → 'Ahmet'")
        var recipient: String
        @Guide(description: "Konu; söylenmediyse boş bırak")
        var subject: String?
        @Guide(description: "E-postanın metni, kullanıcının ağzından birinci tekil şahısla: 'yarın gelemeyeceğimi yaz' → 'Yarın gelemeyeceğim.'")
        var body: String
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let body = arguments.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return .unavailable(name, message: "E-postada ne yazmamı istediğini söylemedin.") }
        let recipient: Recipient?
        do {
            recipient = try await Recipient.resolve(arguments.recipient, as: .email)
        } catch {
            return .unavailable(name, message: error.localizedDescription)
        }
        guard let recipient else {
            return .unavailable(name, message: "\(arguments.recipient) için kayıtlı bir e-posta adresi bulamadım.")
        }
        let subject = arguments.subject?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? Self.subject(from: body)
        return PreparedToolCall(
            toolName: name,
            argumentsDescription: "to: \(recipient.address), subject: \(subject)",
            risk: risk,
            confirmationQuestion: "\(recipient.name), \(recipient.address) adresine \"\(subject)\" konulu e-postayı gönderiyorum: \(Recipient.preview(body)) Göndermem için evet ya da gönder de.",
            requiresExplicitYes: true,
            execute: { await Self.send(to: recipient, subject: subject, body: body) })
    }

    func call(arguments: Arguments) async throws -> String {
        ToolReply.failure("E-posta yalnızca onayla gönderilir.")
    }

    private static func send(to recipient: Recipient, subject: String, body: String) async -> String {
        do {
            try await AppleScriptRunner.runToCompletion("""
            tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:\(AppleScriptRunner.quoted(subject)), content:\(AppleScriptRunner.quoted(body)), visible:false}
            tell newMessage to make new to recipient at end of to recipients with properties {address:\(AppleScriptRunner.quoted(recipient.address))}
            send newMessage
            end tell
            """)
            return "E-posta \(recipient.name) kişisine gönderildi."
        } catch {
            return ToolReply.failure(error)
        }
    }

    private static func subject(from body: String) -> String {
        let firstSentence = body.split(whereSeparator: { ".!?\n".contains($0) }).first.map(String.init) ?? body
        return firstSentence.count <= 50 ? firstSentence : String(firstSentence.prefix(47)) + "…"
    }
}

struct SendMessageTool: AssistantTool {
    let name = "sendMessage"
    let description = "Mesajlar uygulamasıyla birine iMessage gönderir; göndermeden önce kime ne gideceğini okuyup onay ister."
    let risk = ToolRisk.needsConfirmation

    @Generable
    struct Arguments {
        @Guide(description: "Alıcının eksiz adı ya da telefon numarası: 'Ayşe'ye' → 'Ayşe'")
        var recipient: String
        @Guide(description: "Mesajın metni, kullanıcının ağzından birinci tekil şahısla: 'geç kalacağımı yaz' → 'Geç kalacağım.'")
        var text: String
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        let text = arguments.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unavailable(name, message: "Mesajda ne yazmamı istediğini söylemedin.") }
        let recipient: Recipient?
        do {
            recipient = try await Recipient.resolve(arguments.recipient, as: .phone)
        } catch {
            return .unavailable(name, message: error.localizedDescription)
        }
        guard let recipient else {
            return .unavailable(name, message: "\(arguments.recipient) için kayıtlı bir telefon ya da e-posta bulamadım.")
        }
        return PreparedToolCall(
            toolName: name,
            argumentsDescription: "to: \(recipient.address)",
            risk: risk,
            confirmationQuestion: "\(recipient.name), \(recipient.address) için iMessage ile şunu gönderiyorum: \(Recipient.preview(text)) Göndermem için evet ya da gönder de.",
            requiresExplicitYes: true,
            execute: { await Self.send(to: recipient, text: text) })
    }

    func call(arguments: Arguments) async throws -> String {
        ToolReply.failure("Mesaj yalnızca onayla gönderilir.")
    }

    private static func send(to recipient: Recipient, text: String) async -> String {
        do {
            try await AppleScriptRunner.runToCompletion("""
            tell application "Messages"
            set targetService to 1st account whose service type = iMessage
            send \(AppleScriptRunner.quoted(text)) to participant \(AppleScriptRunner.quoted(recipient.address)) of targetService
            end tell
            """)
            return "Mesaj \(recipient.name) kişisine gönderildi."
        } catch {
            return ToolReply.failure(error)
        }
    }
}

/// Unread mail in the inbox. Senders and subjects are untrusted text, answered by the tool-less session.
struct ReadMailTool: AssistantTool {
    let name = "readMail"
    let description = "Mail'deki okunmamış e-postaları söyler: kaç tane olduğunu, kimden geldiklerini ve konularını."
    let answersWithLanguageModel = true
    private static let maxMessages = 8

    @Generable
    struct Arguments {
        @Guide(description: "Belirli bir göndericiden gelenler isteniyorsa onun eksiz adı; yoksa boş bırak")
        var sender: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let filter = arguments.sender?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            .map { " and sender contains \(AppleScriptRunner.quoted($0))" } ?? ""
        do {
            let listing = try await AppleScriptRunner.run("""
            tell application "Mail"
            set unread to (messages of inbox whose read status is false\(filter))
            set total to count of unread
            set output to "Okunmamış e-posta sayısı: " & total
            repeat with i from 1 to (total)
            if i > \(Self.maxMessages) then exit repeat
            set m to item i of unread
            set output to output & linefeed & "- " & (sender of m) & ": " & (subject of m)
            end repeat
            return output
            end tell
            """)
            return listing
        } catch {
            return ToolReply.failure(error)
        }
    }
}
