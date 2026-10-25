/// "Buna yanıt ver: yarın uygunum", "Ahmet'in mailine teşekkür ederim diye cevap yaz"; "reply to this: I'm in",
/// "reply to Ahmet's email saying thanks". The reply text is taken only from the user's own words.
public struct MailReplyRequest: Equatable, Sendable {
    /// Whose message, when named: "Ahmet".
    public let sender: String?
    /// What to write; nil when it was not said.
    public let text: String?

    public init(sender: String?, text: String?) {
        self.sender = sender
        self.text = text
    }

    private static let replyStems = ["yanit", "cevap"]
    private static let replyVerbs: Set<String> = [
        "ver", "verir", "versene", "verebilir", "yaz", "yazar", "yazsana", "yazabilir", "gonder", "gonderir",
        "gondersene", "gonderebilir", "at", "atar", "atsana", "atabilir", "yolla", "yollar", "yollasana",
    ]
    private static let mailStems = ["mail", "eposta", "posta", "ileti"]
    private static let pointers: Set<String> = ["buna", "ona", "suna"]
    private static let determiners: Set<String> = ["bu", "su", "o", "son", "ilk", "gelen"]
    private static let genitiveEndings: Set<String> = ["in", "un", "nin", "nun"]
    private static let dativeEndings: Set<String> = ["e", "a", "ye", "ya", "ne", "na"]

    public static func parse(_ command: String, language: AssistantLanguage = .turkish) -> MailReplyRequest? {
        let words = SpokenWords(command)
        return language == .english ? english(words) : turkish(words)
    }

    /// The request names e-mail ("maile", "e-postasına", "email"), so a reply means a mail reply.
    public static func mentionsMail(_ command: String, language: AssistantLanguage = .turkish) -> Bool {
        let words = SpokenWords(command).folded
        if language == .english { return words.contains { ["email", "mail", "message"].contains($0) } }
        return words.contains { word in mailStems.contains(where: word.hasPrefix) }
    }

    private static func turkish(_ words: SpokenWords) -> MailReplyRequest? {
        let folded = words.folded
        let end = words.contentEnd
        guard let reply = folded.indices.first(where: { index in replyStems.contains(where: folded[index].hasPrefix) }),
              reply < end else { return nil }
        let (sender, phraseEnd) = turkishTarget(words, before: reply)
        let text: String
        if let diye = (phraseEnd..<reply).first(where: { folded[$0] == "diye" }) {
            text = words.text(phraseEnd..<diye)
        } else if reply + 1 < end, folded[reply + 1] == "olarak" {
            // "Yanıt olarak yarın uygunum yaz".
            let verbAtEnd = replyVerbs.contains(folded[end - 1]) ? end - 1 : end
            text = words.text(reply + 2..<verbAtEnd)
        } else {
            let verb = !isReplyVerb(folded[reply]) && reply + 1 < end && replyVerbs.contains(folded[reply + 1]) ? reply + 1 : reply
            text = words.text(verb + 1..<end)
        }
        return MailReplyRequest(sender: sender, text: text.isEmpty ? nil : text)
    }

    /// "yanıtla", "cevapla": the reply word is itself the verb.
    private static func isReplyVerb(_ word: String) -> Bool {
        word.hasPrefix("yanitla") || word.hasPrefix("cevapla")
    }

    /// Reads "buna", "bu maile", "Ahmet'in mailine", "Ahmet'e" from the start; returns the sender and where
    /// the words that may be the reply text begin.
    private static func turkishTarget(_ words: SpokenWords, before reply: Int) -> (sender: String?, end: Int) {
        let folded = words.folded
        var sender: String?
        var index = 0
        while index < reply {
            let word = folded[index]
            let next = index + 1 < reply ? folded[index + 1] : ""
            let isMail = { (word: String) in mailStems.contains(where: word.hasPrefix) }
            if pointers.contains(word) || isMail(word) || (determiners.contains(word) && isMail(next)) {
                index += 1
            } else if let (name, suffix) = words.properName(index),
                      (genitiveEndings.contains(suffix) && isMail(next)) || (dativeEndings.contains(suffix) && index + 1 == reply) {
                sender = name
                index += 1
            } else {
                break
            }
        }
        return (sender, index)
    }

    private static let englishVerbs: Set<String> = ["reply", "respond", "answer", "write"]
    private static let textMarkers: Set<String> = ["saying", "that", "with"]
    private static let notSenders: Set<String> = [
        "to", "the", "this", "that", "it", "email", "mail", "message", "his", "her", "their", "last", "latest", "back",
        "one", "please", "first",
    ]

    private static func english(_ words: SpokenWords) -> MailReplyRequest? {
        let folded = words.folded
        guard let verb = folded.indices.first(where: { englishVerbs.contains(folded[$0]) }), verb <= 1,
              folded[verb] != "write" || (verb + 1 < folded.count && folded[verb + 1] == "back")
        else { return nil }
        let end = words.contentEnd
        let colon = (verb..<end).first(where: words.endsWithColon)
        let marker = colon.map { $0 + 1 } ?? (verb + 1..<end).first(where: { textMarkers.contains(folded[$0]) })
        let phraseEnd = colon.map { $0 + 1 } ?? marker ?? end
        let senderWords = (verb + 1..<phraseEnd).filter { !notSenders.contains(folded[$0]) }
        let sender = senderWords.isEmpty ? nil : senderWords.map { words.text($0..<$0 + 1) }.joined(separator: " ")
            .replacingOccurrences(of: "'s", with: "").replacingOccurrences(of: "’s", with: "")
        let textStart = colon.map { $0 + 1 } ?? marker.map { $0 + 1 }
        let text = textStart.map { words.text($0..<end) } ?? ""
        return MailReplyRequest(sender: sender, text: text.isEmpty ? nil : text)
    }
}
