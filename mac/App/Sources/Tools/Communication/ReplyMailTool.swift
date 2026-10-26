import AsistanCore
import Foundation
import FoundationModels

/// "Buna yanıt ver: yarın uygunum", "Ahmet'in mailine teşekkür ederim diye cevap yaz". Answers a message
/// readMail just read, with Mail's own reply. The text comes only from the user's words, never from the
/// model or the mail, and the recipient and text are read out before an explicit yes.
struct ReplyMailTool: AssistantTool {
    let name = "replyMail"
    let description = "Az önce okunan bir e-postaya Mail'de yanıt gönderir; göndermeden önce kime ne gideceğini okuyup onay ister ('buna yanıt ver: yarın uygunum')."
    let risk = ToolRisk.needsConfirmation
    let context: ConversationContext
    private static let listedMessages = 4

    @Generable
    struct Arguments {
        @Guide(description: "Kullanıcının isteği, olduğu gibi")
        var request: String
    }

    /// The model is never asked: its prompt holds the previous answer, which may quote the mail.
    func arguments(fromCommand command: String) -> Arguments? {
        Arguments(request: command)
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        guard let request = MailReplyRequest.parse(arguments.request, language: AppLanguage.current) else {
            return .unavailable(name, message: String(localized: "Hangi e-postaya ne yanıt vereceğimi anlayamadım. Örneğin 'buna yanıt ver: yarın uygunum' diyebilirsin."))
        }
        guard let text = request.text else {
            return .unavailable(name, message: String(localized: "Yanıtta ne yazmamı istediğini söyler misin? Örneğin 'buna yanıt ver: yarın uygunum'."))
        }
        let read = await MainActor.run { context.recentMail(at: .now) }
        var target = MailReference.target(sender: request.sender, in: read)
        if target == .none, let sender = request.sender {
            do {
                target = try await Self.latestMessage(from: sender).map { .message($0) } ?? .none
            } catch {
                return .unavailable(name, message: error.localizedDescription)
            }
        }
        switch target {
        case .none:
            return .unavailable(name, message: request.sender.map { String(localized: "\($0) kişisinden gelen bir e-posta bulamadım.") }
                ?? String(localized: "Hangi e-postaya yanıt vereceğimi bilmiyorum; önce 'maillerimi oku' diyebilirsin."))
        case let .several(messages):
            let list = messages.prefix(Self.listedMessages).map { "\(Self.sender(of: $0)): \($0.subject)" }.joined(separator: "; ")
            return .unavailable(name, message: String(localized: "Hangi e-postaya yanıt vereyim? Az önce okuduklarım: \(list). Örneğin 'Ahmet'in mailine … diye yanıt ver' diyebilirsin."))
        case let .message(message):
            return PreparedToolCall(
                toolName: name,
                argumentsDescription: "reply to: \(message.id)",
                risk: risk,
                confirmationQuestion: String(localized: "\(Self.sender(of: message)), \(message.senderAddress) adresinden gelen \"\(message.subject)\" konulu e-postaya şu yanıtı gönderiyorum: \(Recipient.preview(text)). Göndermem için evet ya da gönder de."),
                requiresExplicitYes: true,
                execute: { await Self.send(text, replyingTo: message) })
        }
    }

    func call(arguments: Arguments) async throws -> String {
        ToolReply.failure(String(localized: "E-posta yalnızca onayla gönderilir."))
    }

    private static func sender(of message: MailReference) -> String {
        message.senderName.isEmpty ? message.senderAddress : message.senderName
    }

    /// The newest inbox message from `sender`, read or not, for "Ahmet'in mailine …" without a reading first.
    private static func latestMessage(from sender: String) async throws -> MailReference? {
        let output = try await AppleScriptRunner.run("""
        tell application "Mail"
        set found to (messages of inbox whose sender contains \(AppleScriptRunner.quoted(sender)))
        if (count of found) = 0 then return ""
        set newest to item 1 of found
        repeat with m in found
        if (date received of m) > (date received of newest) then set newest to contents of m
        end repeat
        \(ReadMailTool.setReference("newest", flag: "\"0\"", into: "refLine"))
        return refLine
        end tell
        """)
        return MailReadOutput.split(output).references.first
    }

    /// Mail's reply keeps the thread and the recipient; only the user's words go in as its content.
    private static func send(_ text: String, replyingTo message: MailReference) async -> String {
        guard !message.id.isEmpty, message.id.allSatisfy(\.isNumber) else {
            return ToolReply.failure(String(localized: "Yanıtlanacak e-posta bulunamadı."))
        }
        do {
            let result = try await Task {
                try await AppleScriptRunner.run("""
                tell application "Mail"
                set found to (messages of inbox whose id is \(message.id))
                if (count of found) = 0 then return "missing"
                set replyMessage to reply (item 1 of found) without opening window
                set content of replyMessage to \(AppleScriptRunner.quoted(text))
                send replyMessage
                return "sent"
                end tell
                """)
            }.value
            return result.trimmingCharacters(in: .whitespacesAndNewlines) == "sent"
                ? String(localized: "Yanıt \(sender(of: message)) kişisine gönderildi.")
                : ToolReply.failure(String(localized: "Yanıtlanacak e-posta bulunamadı."))
        } catch {
            return ToolReply.failure(error)
        }
    }
}
