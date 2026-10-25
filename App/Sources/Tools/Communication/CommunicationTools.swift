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
        text.count <= previewCharacters ? text : String(text.prefix(previewCharacters)) + String(localized: "… (devamı var).")
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

/// What a message carries: the words as said, or, when they only point ("bunu gönder"), what is on
/// screen: the selected text, the page's title and address, or the selected files as attachments.
struct MessageContent: Sendable {
    let body: String
    let attachments: [URL]

    private static let maxPointedText = 2000
    private static let maxAttachments = 5

    static func resolve(_ said: String, context: ConversationContext) async -> MessageContent? {
        let trimmed = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ContextIntent.onlyPoints(trimmed, language: AppLanguage.current) else { return MessageContent(body: trimmed, attachments: []) }
        let item = await MainActor.run {
            context.screen.flatMap { ContextResolver.resolve(ContextIntent.wantedKind(in: trimmed, language: AppLanguage.current), in: $0) }
        }
        switch item {
        case let .text(text)?:
            return MessageContent(body: String(text.prefix(maxPointedText)), attachments: [])
        case let .page(url, title)?:
            return MessageContent(body: [title, url.absoluteString].compactMap { $0 }.joined(separator: "\n"), attachments: [])
        case let .files(urls)?:
            let files = urls.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            return files.isEmpty ? nil : MessageContent(body: "", attachments: Array(files.prefix(maxAttachments)))
        case let .document(url)?:
            return MessageContent(body: "", attachments: [url])
        case nil:
            return nil
        }
    }

    /// "rapor.pdf" or "rapor.pdf ve 2 dosya daha", for the confirmation question.
    var spokenAttachments: String? {
        guard let first = attachments.first else { return nil }
        return attachments.count == 1
            ? first.lastPathComponent
            : String(localized: "\(first.lastPathComponent) ve \(attachments.count - 1) dosya daha")
    }
}

struct SendEmailTool: AssistantTool {
    let name = "sendEmail"
    let description = "Mail uygulamasıyla birine e-posta gönderir; göndermeden önce kime ne gideceğini okuyup onay ister."
    let risk = ToolRisk.needsConfirmation
    let context: ConversationContext

    @Generable
    struct Arguments {
        @Guide(description: "Alıcının eksiz adı ya da e-posta adresi: 'Ahmet'e' → 'Ahmet'")
        var recipient: String
        @Guide(description: "Konu; söylenmediyse boş bırak")
        var subject: String?
        @Guide(description: "E-postanın metni, kullanıcının ağzından birinci tekil şahısla: 'yarın gelemeyeceğimi yaz' → 'Yarın gelemeyeceğim.'; 'bunu gönder' deniyorsa 'bunu'")
        var body: String
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        guard let content = await MessageContent.resolve(arguments.body, context: context),
              !content.body.isEmpty || !content.attachments.isEmpty else {
            return .unavailable(name, message: String(localized: "E-postada ne göndermemi istediğini anlayamadım. Bir metni ya da dosyayı seçip 'bunu gönder' diyebilirsin."))
        }
        let body = content.body
        let recipient: Recipient?
        do {
            recipient = try await Recipient.resolve(arguments.recipient, as: .email)
        } catch {
            return .unavailable(name, message: error.localizedDescription)
        }
        guard let recipient else {
            return .unavailable(name, message: String(localized: "\(arguments.recipient) için kayıtlı bir e-posta adresi bulamadım."))
        }
        let subject = arguments.subject?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? (body.isEmpty ? content.attachments.first?.deletingPathExtension().lastPathComponent ?? "" : Self.subject(from: body))
        let attached = content.spokenAttachments.map { String(localized: ", ekinde \($0)") } ?? ""
        let preview = body.isEmpty ? "" : ": \(Recipient.preview(body))"
        return PreparedToolCall(
            toolName: name,
            argumentsDescription: "to: \(recipient.address), subject: \(subject), attachments: \(content.attachments.count)",
            risk: risk,
            confirmationQuestion: String(localized: "\(recipient.name), \(recipient.address) adresine \"\(subject)\" konulu e-postayı gönderiyorum\(attached)\(preview). Göndermem için evet ya da gönder de."),
            requiresExplicitYes: true,
            execute: { await Self.send(to: recipient, subject: subject, body: body, attachments: content.attachments) })
    }

    func call(arguments: Arguments) async throws -> String {
        ToolReply.failure(String(localized: "E-posta yalnızca onayla gönderilir."))
    }

    /// Mail needs a moment to take in attachments before it sends.
    private static let attachmentSettleSeconds = 2

    private static func send(to recipient: Recipient, subject: String, body: String, attachments: [URL]) async -> String {
        let attaching = attachments.map { file in
            "make new attachment with properties {file name:(POSIX file \(AppleScriptRunner.quoted(file.path)) as alias)} at after the last paragraph"
        }.joined(separator: "\n")
        do {
            try await AppleScriptRunner.runToCompletion("""
            tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:\(AppleScriptRunner.quoted(subject)), content:\(AppleScriptRunner.quoted(body.isEmpty ? " " : body)), visible:false}
            tell newMessage
            make new to recipient at end of to recipients with properties {address:\(AppleScriptRunner.quoted(recipient.address))}
            \(attaching)
            end tell
            \(attachments.isEmpty ? "" : "delay \(attachmentSettleSeconds)")
            send newMessage
            end tell
            """)
            return String(localized: "E-posta \(recipient.name) kişisine gönderildi.")
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
    let context: ConversationContext

    @Generable
    struct Arguments {
        @Guide(description: "Alıcının eksiz adı ya da telefon numarası: 'Ayşe'ye' → 'Ayşe'")
        var recipient: String
        @Guide(description: "Mesajın metni, kullanıcının ağzından birinci tekil şahısla: 'geç kalacağımı yaz' → 'Geç kalacağım.'; 'bunu gönder' deniyorsa 'bunu'")
        var text: String
    }

    func makeCall(_ arguments: Arguments) async -> PreparedToolCall {
        guard let content = await MessageContent.resolve(arguments.text, context: context),
              !content.body.isEmpty || !content.attachments.isEmpty else {
            return .unavailable(name, message: String(localized: "Mesajda ne göndermemi istediğini anlayamadım. Bir metni ya da dosyayı seçip 'bunu gönder' diyebilirsin."))
        }
        let text = content.body
        let recipient: Recipient?
        do {
            recipient = try await Recipient.resolve(arguments.recipient, as: .phone)
        } catch {
            return .unavailable(name, message: error.localizedDescription)
        }
        guard let recipient else {
            return .unavailable(
                name, message: String(localized: "\(arguments.recipient) için kayıtlı bir telefon ya da e-posta bulamadım."))
        }
        return PreparedToolCall(
            toolName: name,
            argumentsDescription: "to: \(recipient.address)",
            risk: risk,
            confirmationQuestion: Self.question(to: recipient, text: text, attachments: content.spokenAttachments),
            requiresExplicitYes: true,
            execute: { await Self.send(to: recipient, text: text, attachments: content.attachments) })
    }

    /// Whole sentences per case, so each language can order the parts its own way.
    private static func question(to recipient: Recipient, text: String, attachments: String?) -> String {
        let (name, address) = (recipient.name, recipient.address)
        let preview = Recipient.preview(text)
        switch (attachments, text.isEmpty) {
        case let (file?, false):
            return String(localized: "\(name), \(address) için iMessage ile \(file) dosyasını şunu gönderiyorum: \(preview). Göndermem için evet ya da gönder de.")
        case let (file?, true):
            return String(localized: "\(name), \(address) için iMessage ile \(file) dosyasını gönderiyorum. Göndermem için evet ya da gönder de.")
        case (nil, false):
            return String(localized: "\(name), \(address) için iMessage ile şunu gönderiyorum: \(preview). Göndermem için evet ya da gönder de.")
        case (nil, true):
            return String(localized: "\(name), \(address) için iMessage ile gönderiyorum. Göndermem için evet ya da gönder de.")
        }
    }

    func call(arguments: Arguments) async throws -> String {
        ToolReply.failure(String(localized: "Mesaj yalnızca onayla gönderilir."))
    }

    private static func send(to recipient: Recipient, text: String, attachments: [URL]) async -> String {
        let sends = attachments.map { "send (POSIX file \(AppleScriptRunner.quoted($0.path))) to targetBuddy" }
            + (text.isEmpty ? [] : ["send \(AppleScriptRunner.quoted(text)) to targetBuddy"])
        do {
            try await AppleScriptRunner.runToCompletion("""
            tell application "Messages"
            set targetService to 1st account whose service type = iMessage
            set targetBuddy to participant \(AppleScriptRunner.quoted(recipient.address)) of targetService
            \(sends.joined(separator: "\n"))
            end tell
            """)
            return String(localized: "Mesaj \(recipient.name) kişisine gönderildi.")
        } catch {
            return ToolReply.failure(error)
        }
    }
}

/// Unread mail in the inbox. Senders and subjects are untrusted text, answered by the tool-less session.
/// The messages listed are remembered, so "buna yanıt ver" can answer one of them.
struct ReadMailTool: AssistantTool {
    let name = "readMail"
    let description = "Mail'deki okunmamış e-postaları söyler: kaç tane olduğunu, kimden geldiklerini, konularını ve istenirse ne yazdıklarını."
    let answersWithLanguageModel = true
    let context: ConversationContext
    private static let maxMessages = 8
    /// Messages whose text is read; each is cut, so a newsletter can't fill the answer.
    private static let maxReadMessages = 3
    private static let maxBodyCharacters = 1500

    @Generable
    struct Arguments {
        @Guide(description: "Belirli bir göndericiden gelenler isteniyorsa onun eksiz adı; yoksa boş bırak")
        var sender: String?
        @Guide(description: "E-postaların ne yazdığı, içeriği isteniyorsa true")
        var withContent: Bool
    }

    /// "İçeriğini oku" asks for the text even when the model only lists the messages again.
    func refine(_ arguments: Arguments, command: String) -> Arguments {
        var refined = arguments
        refined.withContent = arguments.withContent || MailRequest.asksForContent(command)
        return refined
    }

    func call(arguments: Arguments) async throws -> String {
        let filter = arguments.sender?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            .map { " and sender contains \(AppleScriptRunner.quoted($0))" } ?? ""
        let bodies = arguments.withContent ? """
            repeat with i from 1 to (total)
            if i > \(Self.maxReadMessages) then exit repeat
            set m to item i of unread
            \(Self.cleaned("content of m", into: "body", oneLine: false))
            if length of body > \(Self.maxBodyCharacters) then set body to text 1 thru \(Self.maxBodyCharacters) of body
            \(Self.cleaned("sender of m", into: "shownSender", oneLine: true))
            \(Self.cleaned("subject of m", into: "shownSubject", oneLine: true))
            set output to output & linefeed & linefeed & \(AppleScriptRunner.quoted(String(localized: "E-posta "))) & i & ": " & shownSender & " - " & shownSubject & linefeed & body
            end repeat
            """ : ""
        let contentRead = arguments.withContent ? Self.maxReadMessages : 0
        do {
            let output = try await AppleScriptRunner.run("""
            tell application "Mail"
            set unread to (messages of inbox whose read status is false\(filter))
            set total to count of unread
            set output to \(AppleScriptRunner.quoted(String(localized: "Okunmamış e-posta sayısı: "))) & total
            set refs to ""
            repeat with i from 1 to (total)
            if i > \(Self.maxMessages) then exit repeat
            set m to item i of unread
            \(Self.cleaned("sender of m", into: "shownSender", oneLine: true))
            \(Self.cleaned("subject of m", into: "shownSubject", oneLine: true))
            set output to output & linefeed & "- " & shownSender & ": " & shownSubject
            set readFlag to "0"
            if i is not greater than \(contentRead) then set readFlag to "1"
            \(Self.setReference("m", flag: "readFlag", into: "refLine"))
            set refs to refs & linefeed & refLine
            end repeat
            \(bodies)
            return output & refs
            end tell
            """)
            let (text, references) = MailReadOutput.split(output)
            await MainActor.run { context.keepReadMail(references, at: .now) }
            return text
        } catch {
            return ToolReply.failure(error)
        }
    }

    /// Statements setting `variable` to the `MailReadOutput` line for the message in the AppleScript variable
    /// `message`; the marker's control character is built in the script rather than written into its source.
    static func setReference(_ message: String, flag: String, into variable: String) -> String {
        let marker = "(character id \(MailReadOutput.marker.unicodeScalars.first!.value)) & "
            + AppleScriptRunner.quoted(String(MailReadOutput.marker.dropFirst()))
        let fields = [marker, "(id of \(message) as text)", "refName", "refAddress", "refSubject", flag]
        return [
            cleaned("extract name from (sender of \(message))", into: "refName", oneLine: true),
            cleaned("extract address from (sender of \(message))", into: "refAddress", oneLine: true),
            cleaned("subject of \(message)", into: "refSubject", oneLine: true),
            "set \(variable) to " + fields.joined(separator: " & tab & "),
        ].joined(separator: "\n")
    }

    /// Statements setting `variable` to the text of `expression` without the marker's control character, so a
    /// sender, subject or body can't add a reference line of its own; one-line fields also lose line breaks and tabs.
    static func cleaned(_ expression: String, into variable: String, oneLine: Bool) -> String {
        let marker = "character id \(MailReadOutput.marker.unicodeScalars.first!.value)"
        let delimiters = oneLine ? "{\(marker), linefeed, return, tab}" : "{\(marker)}"
        return """
        set AppleScript's text item delimiters to \(delimiters)
        set \(variable) to text items of ((\(expression)) as text)
        set AppleScript's text item delimiters to \(oneLine ? "\" \"" : "\"\"")
        set \(variable) to \(variable) as text
        set AppleScript's text item delimiters to ""
        """
    }
}
