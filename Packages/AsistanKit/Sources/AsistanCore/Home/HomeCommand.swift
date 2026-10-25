import Foundation

/// Smart-home commands for Home Assistant: whether a command names a home device or room ("salonun ışığını aç",
/// "klimayı 22 dereceye ayarla", "kapı kilitli mi"), and whether it changes something that guards the house (a lock,
/// the garage door, the alarm) and so needs a yes first.
public enum HomeCommand {
    /// Folded word beginnings: "ışığını" → "isigini", "mutfağın" → "mutfagin".
    private static let turkishDevices = [
        "isik", "isig", "lamba", "avize", "klima", "priz", "perde", "panjur", "stor", "kilit", "kilid", "termostat",
        "kombi", "isitici", "petek", "salon", "mutfa", "garaj", "banyo", "koridor", "balkon",
    ]
    private static let turkishPhrases = [("yatak", "odas"), ("oturma", "odas"), ("cocuk", "odas"), ("calisma", "odas"),
                                         ("ev", "alarm"), ("guvenlik", "alarm")]
    private static let englishDevices: Set<String> = [
        "light", "lights", "lamp", "lamps", "thermostat", "plug", "plugs", "outlet", "outlets", "curtain", "curtains",
        "blind", "blinds", "shutter", "shutters", "lock", "locked", "unlock", "garage", "kitchen", "bedroom",
        "hallway", "heater", "heating",
    ]
    private static let englishPhrases = [("living", "room"), ("air", "conditioning"), ("air", "conditioner"), ("front", "door"),
                                         ("house", "alarm"), ("security", "alarm"), ("the", "ac")]
    /// "ekranın ışığını kıs", "bilgisayarı kilitle", "keyboard light": this Mac, not the house.
    private static let computer = ["ekran", "bilgisayar", "klavye", "mac", "telefon", "oturum", "screen", "computer",
                                   "keyboard", "display", "laptop", "phone"]
    private static let turkishGuards = ["kilit", "kilid", "garaj", "alarm"]
    private static let englishGuards = ["lock", "unlock", "garage", "alarm"]
    private static let turkishQuestion: Set<String> = [
        "mi", "mı", "mu", "mü", "misin", "mıdır", "midir", "mudur", "müdür", "ne", "kaç", "nedir", "hangi",
    ]
    private static let englishQuestion: Set<String> = ["is", "are", "what", "which", "how", "did", "does", "do"]

    public static func namesHomeDevice(_ command: String, language: AssistantLanguage) -> Bool {
        let words = folded(command)
        if words.contains(where: { word in computer.contains(where: word.hasPrefix) }) { return false }
        if language == .english {
            return words.contains(where: englishDevices.contains) || hasPhrase(words, englishPhrases)
        }
        return words.contains { word in turkishDevices.contains(where: word.hasPrefix) } || hasPhrase(words, turkishPhrases)
    }

    /// Changes a lock, the garage door or the alarm; asking whether the door is locked changes nothing.
    public static func guardsTheHouse(_ command: String, language: AssistantLanguage) -> Bool {
        let guards = language == .english ? englishGuards : turkishGuards
        return folded(command).contains { word in guards.contains(where: word.hasPrefix) } && !isQuestion(command, language: language)
    }

    public static func isQuestion(_ command: String, language: AssistantLanguage) -> Bool {
        if command.trimmingCharacters(in: .whitespaces).hasSuffix("?") { return true }
        if language == .english { return folded(command).first.map(englishQuestion.contains) ?? false }
        // The question particle is its own word ("kilitli mi"); folding would mix "mi" with "mı".
        let punctuation = CharacterSet(charactersIn: "?.,!")
        return TurkishText.lowercased(command).split(separator: " ").contains { word in
            turkishQuestion.contains(word.trimmingCharacters(in: punctuation))
        }
    }

    private static func folded(_ command: String) -> [String] {
        TurkishText.folded(command).split(separator: " ").map(String.init)
    }

    private static func hasPhrase(_ words: [String], _ phrases: [(String, String)]) -> Bool {
        zip(words, words.dropFirst()).contains { first, second in
            phrases.contains { first == $0.0 && second.hasPrefix($0.1) }
        }
    }
}

/// Home Assistant's REST API as the assistant uses it: the conversation endpoint, which understands the command in its
/// own language and answers with a sentence to say, and the status endpoint for testing the connection.
public enum HomeAssistantAPI {
    public enum ResponseError: Error, Equatable {
        case unexpected
    }

    public static let conversationPath = "api/conversation/process"
    public static let statusPath = "api/"

    /// "http://homeassistant.local:8123/" → "http://homeassistant.local:8123"; nil for anything that isn't a plain
    /// http(s) address (a user name in it, a query, another scheme, a port that isn't a number).
    public static func baseAddress(_ address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil
        else { return nil }
        var base = URLComponents()
        base.scheme = scheme
        base.host = host
        base.port = components.port
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        base.path = path
        return base.url
    }

    /// The HTTP request for POST {address}/api/conversation/process with the bearer token.
    public static func conversationRequest(_ text: String, language: AssistantLanguage, base: URL, token: String) -> Data {
        let body = try! JSONSerialization.data(withJSONObject: ["text": text, "language": language.code], options: [.sortedKeys])
        return HTTPRequest.post(base.appending(path: conversationPath), headers: headers(token: token) + [("Content-Type", "application/json")],
                                body: body)
    }

    /// GET {address}/api/: answers only when the address is Home Assistant and the token is accepted.
    public static func statusRequest(base: URL, token: String) -> Data {
        HTTPRequest.get(base.appending(path: statusPath), headers: headers(token: token))
    }

    /// response.speech.plain.speech from the conversation endpoint; nil when Home Assistant said nothing. Throws when
    /// the answer is not a conversation response at all.
    public static func spokenReply(from data: Data) throws(ResponseError) -> String? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = payload["response"] as? [String: Any] else { throw .unexpected }
        let speech = response["speech"] as? [String: Any]
        let plain = speech?["plain"] as? [String: Any]
        let said = (plain?["speech"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return said?.isEmpty == false ? said : nil
    }

    private static func headers(token: String) -> [(String, String)] {
        [("Authorization", "Bearer \(token)"), ("Accept", "application/json")]
    }
}
