import Foundation

/// A message readMail read out, kept so "buna yanıt ver" knows which one "this" is.
public struct MailReference: Equatable, Sendable {
    /// Mail's numeric message id.
    public let id: String
    public let senderName: String
    public let senderAddress: String
    public let subject: String
    /// Its text was read, not only its sender and subject.
    public let contentWasRead: Bool

    public init(id: String, senderName: String, senderAddress: String, subject: String, contentWasRead: Bool) {
        self.id = id
        self.senderName = senderName
        self.senderAddress = senderAddress
        self.subject = subject
        self.contentWasRead = contentWasRead
    }

    public enum Target: Equatable, Sendable {
        case message(MailReference)
        case several([MailReference])
        case none
    }

    /// The message a reply goes to: the one from `sender`, else the only one whose text was read, else the only
    /// one listed. Several candidates are returned for the user to choose from rather than guessed.
    public static func target(sender: String?, in references: [MailReference]) -> Target {
        if let sender {
            let named = references.filter { reference in
                PhraseMatcher.matches(sender, title: reference.senderName)
                    || PhraseMatcher.matches(sender, title: localPart(of: reference.senderAddress))
            }
            return target(among: named)
        }
        let read = references.filter(\.contentWasRead)
        if read.count == 1 { return .message(read[0]) }
        return target(among: read.isEmpty ? references : read)
    }

    private static func target(among references: [MailReference]) -> Target {
        switch references.count {
        case 0: .none
        case 1: .message(references[0])
        default: .several(references)
        }
    }

    /// "ahmet.yilmaz@example.com" → "ahmet yilmaz".
    private static func localPart(of address: String) -> String {
        String(address.prefix { $0 != "@" }).replacingOccurrences(of: #"[._\-+]"#, with: " ", options: .regularExpression)
    }
}

/// readMail's script prints one line per listed message after what it reads: the marker, then id, sender
/// name, sender address, subject and whether its text was read, separated by tabs. Those lines are split off
/// before the rest goes to the language model.
public enum MailReadOutput {
    public static let marker = "\u{1F}MAILREF"

    public static func split(_ output: String) -> (text: String, references: [MailReference]) {
        var text: [Substring] = []
        var references: [MailReference] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix(marker) else {
                text.append(line)
                continue
            }
            let fields = line.dropFirst(marker.count).split(separator: "\t", omittingEmptySubsequences: false).dropFirst()
            guard fields.count >= 5, let id = fields.first, !id.isEmpty, id.allSatisfy(\.isNumber) else { continue }
            let values = Array(fields)
            references.append(MailReference(id: String(id), senderName: String(values[1]), senderAddress: String(values[2]),
                                            subject: values[3..<values.count - 1].joined(separator: "\t"),
                                            contentWasRead: values[values.count - 1] == "1"))
        }
        return (text.joined(separator: "\n").trimmingCharacters(in: .newlines), references)
    }
}
