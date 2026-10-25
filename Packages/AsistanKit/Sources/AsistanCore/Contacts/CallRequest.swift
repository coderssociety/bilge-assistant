import Foundation

/// "Annemi ara", "Ahmet'i FaceTime'la ara", "Ayşe'yi sesli ara", "anneme telefon et"; "call mom". Told apart
/// from a web search, which "ara" also means: "Atatürk'ü internette ara" names where to search, and
/// "kediyi ara" names no person.
public struct CallRequest: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// A phone call, made through the iPhone when Continuity calling is on.
        case phone
        case faceTimeAudio
        case faceTimeVideo
    }

    /// The person as said, without the case ending: "Ahmet Yılmaz", "annem".
    public let name: String
    public let mode: Mode
    /// False for a bare "<Ad>'ı ara": with nobody of that name in Contacts it was a web search.
    public let isCertain: Bool

    public init(name: String, mode: Mode, isCertain: Bool) {
        self.name = name
        self.mode = mode
        self.isCertain = isCertain
    }

    private static let callVerbs: Set<String> = ["ara", "arar", "arasana", "arayabilir", "arayin", "arayiver"]
    private static let phoneVerbs: Set<String> = ["et", "eder", "etsene", "edebilir", "ac", "acar", "acsana", "acabilir"]
    private static let searchWords = ["google", "youtube", "internet", "web", "vikipedi", "wikipedia", "harita", "tarayici",
                                      "hakkinda", "bilgi", "haber"]
    /// Kinship words with "my", as people are saved in Contacts: "Annem", "Babam".
    private static let kinship: Set<String> = [
        "annem", "babam", "esim", "karim", "kocam", "kardesim", "ablam", "abim", "agabeyim", "teyzem", "halam", "dayim",
        "amcam", "dedem", "ninem", "anneannem", "babaannem", "oglum", "kizim", "sevgilim", "nisanlim", "yegenim",
        "kuzenim", "enistem", "yengem", "patronum", "mudurum", "hocam",
    ]
    private static let accusativeEndings: Set<String> = ["i", "u", "yi", "yu", "ni", "nu"]
    private static let dativeEndings: Set<String> = ["e", "a", "ye", "ya", "ne", "na"]
    private static let nameFillers: Set<String> = ["lutfen", "bilge", "hemen", "simdi", "bir"]

    public static func parse(_ command: String, language: AssistantLanguage = .turkish) -> CallRequest? {
        let words = SpokenWords(command)
        return language == .english ? english(words) : turkish(words)
    }

    private static func turkish(_ words: SpokenWords) -> CallRequest? {
        let folded = words.folded
        let end = words.contentEnd
        guard end >= 2, !folded.contains(where: { word in searchWords.contains(where: word.hasPrefix) }) else { return nil }
        let mode = mode(of: folded)
        let explicit = folded.contains { isCallWord($0) }
        let verb = folded[end - 1]
        if callVerbs.contains(verb), let target = (0..<end - 1).last(where: { !isModeWord(folded[$0]) }) {
            return person(at: target, in: words, endings: accusativeEndings, mode: mode, explicit: explicit)
        }
        // "Anneme telefon et", "Ahmet'e telefon aç".
        if phoneVerbs.contains(verb), end >= 3, folded[end - 2] == "telefon" {
            return person(at: end - 3, in: words, endings: dativeEndings, mode: .phone, explicit: true)
        }
        return nil
    }

    private static func person(at index: Int, in words: SpokenWords, endings: Set<String>, mode: Mode,
                               explicit: Bool) -> CallRequest? {
        let word = words.folded[index]
        if let relative = kinship.first(where: { word.hasPrefix($0) && endings.contains(String(word.dropFirst($0.count))) }) {
            let said = words.text(index..<index + 1)
            return CallRequest(name: String(said.prefix(relative.count)), mode: mode, isCertain: true)
        }
        if let (name, suffix) = words.properName(index), endings.contains(suffix) {
            var first = index
            while first > 0, words.isCapitalized(first - 1), words.properName(first - 1) == nil,
                  !nameFillers.contains(words.folded[first - 1]) {
                first -= 1
            }
            let given = first < index ? words.text(first..<index) + " " : ""
            return CallRequest(name: given + name, mode: mode, isCertain: explicit)
        }
        // Without an apostrophe "ahmeti" could be anything ("kediyi ara"); only a call word makes it a person.
        guard explicit, !word.isEmpty else { return nil }
        return CallRequest(name: words.text(index..<index + 1), mode: mode, isCertain: true)
    }

    /// "FaceTime'la", "telefonla", "sesli": words that only a call has.
    private static func isCallWord(_ word: String) -> Bool {
        word.hasPrefix("facetime") || word.hasPrefix("telefon") || word.hasPrefix("video") || word == "sesli" || word == "goruntulu"
    }

    private static func isModeWord(_ word: String) -> Bool {
        isCallWord(word) || word == "ile" || word == "uzerinden"
    }

    private static func mode(of folded: [String]) -> Mode {
        if folded.contains(where: { $0 == "goruntulu" || $0.hasPrefix("video") }) { return .faceTimeVideo }
        if folded.contains(where: { $0 == "sesli" || $0.hasPrefix("facetime") }) { return .faceTimeAudio }
        return .phone
    }

    private static let englishVerbs: Set<String> = ["call", "phone", "ring", "facetime", "dial"]
    private static let englishFillers: Set<String> = [
        "please", "now", "up", "on", "via", "using", "with", "over", "facetime", "audio", "video", "my", "the", "phone",
        "iphone", "a", "call", "for", "me", "right", "away",
    ]
    private static let notPeople: Set<String> = ["me", "it", "this", "that", "them", "him", "her", "number"]

    /// "Call mom", "FaceTime Ahmet", "video call Ayşe", "call Ahmet on FaceTime audio".
    private static func english(_ words: SpokenWords) -> CallRequest? {
        let folded = words.folded
        let video = folded.first == "video"
        let start = video ? 1 : 0
        guard folded.count > start + 1, englishVerbs.contains(folded[start]), !notPeople.contains(folded[start + 1])
        else { return nil }
        let nameIndices = (start + 1..<words.contentEnd).filter { !englishFillers.contains(folded[$0]) }
        guard let first = nameIndices.first, let last = nameIndices.last else { return nil }
        let mode: Mode = video || folded.contains("video") ? .faceTimeVideo
            : folded.contains("facetime") || folded.contains("audio") ? .faceTimeAudio : .phone
        return CallRequest(name: words.text(first..<last + 1), mode: mode, isCertain: true)
    }

    /// The number or address to call and the URL that starts the call. A phone call needs a phone number;
    /// FaceTime also takes an e-mail address.
    public static func destination(for mode: Mode, phones: [String], emails: [String]) -> (address: String, url: URL)? {
        let phone = phones.lazy.compactMap { said in PhoneNumber.normalized(said).map { (said, $0) } }.first
        switch mode {
        case .phone:
            return phone.flatMap { said, number in URL(string: "tel:\(number)").map { (said, $0) } }
        case .faceTimeAudio, .faceTimeVideo:
            let scheme = mode == .faceTimeAudio ? "facetime-audio" : "facetime"
            let address = phone ?? emails.first.map { ($0, $0) }
            return address.flatMap { said, target in URL(string: "\(scheme)://\(target)").map { (said, $0) } }
        }
    }
}
