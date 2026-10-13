/// Recognizes requests about the assistant's memory without the model. "Hatırla" (remember) and
/// "hatırlat" (remind) differ by one letter, and the router model cannot be trusted to tell them apart.
public enum MemoryIntent: Equatable, Sendable {
    case remember, forget, list

    public enum ForgetTarget: Equatable, Sendable {
        case all, latest
        case matching(String)
    }

    private static let rememberWords: Set<String> = [
        "hatirla", "hatirlasana", "hatirlayin", "hatirlamani", "unutma", "unutmayin", "unutmasana",
    ]
    private static let forgetWords: Set<String> = ["unut", "unutsana", "unutun", "unutur"]
    private static let clearVerbs: Set<String> = ["sil", "temizle", "bosalt", "sifirla"]
    private static let questionWords: Set<String> = ["ne", "neler", "neleri", "nedir"]
    private static let fillerWords: Set<String> = ["sunu", "bunu", "lutfen"]
    private static let forgetFillers: Set<String> = [
        "ilgili", "hakkindaki", "bilgiyi", "bilgileri", "bilgi", "kaydi", "seyi", "olan", "musun", "misin", "artik",
    ]

    public static func parse(_ command: String) -> MemoryIntent? {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        if words.contains(where: { $0.hasPrefix("hatirlat") }) { return nil }
        let mentionsMemory = words.contains { $0.hasPrefix("hafiza") }
        let asks = words.contains(where: questionWords.contains)
        if (words.contains("hatirliyorsun") && asks) || (words.contains("hakkimda") && words.contains("biliyorsun"))
            || (mentionsMemory && asks) {
            return .list
        }
        if words.contains(where: forgetWords.contains) || (mentionsMemory && words.contains(where: clearVerbs.contains)) {
            return .forget
        }
        if words.contains(where: rememberWords.contains) || containsPhrase(words, "aklinda", ["tut", "olsun", "tutar"]) {
            return .remember
        }
        return nil
    }

    /// "Her şeyi unut" → all, "Bunu unut" → the latest fact, "Kahveyle ilgili bilgiyi unut" → "Kahveyle".
    public static func forgetTarget(from command: String) -> ForgetTarget {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        let words = tokens.map { TurkishText.folded($0) }
        let clearsMemory = words.contains { $0.hasPrefix("hafiza") } && words.contains(where: clearVerbs.contains)
        if clearsMemory || containsPhrase(words, "her", ["seyi"]) || words.contains("hepsini") { return .all }
        let kept = zip(tokens, words).filter { _, word in
            !word.isEmpty && !forgetWords.contains(word) && !forgetFillers.contains(word) && !fillerWords.contains(word)
        }
        let query = kept.map(\.0).joined(separator: " ").trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return query.isEmpty ? .latest : .matching(query)
    }

    /// The fact itself, without the request words: "Şunu hatırla: kapı şifresi değişti" → "kapı şifresi değişti".
    /// nil when nothing is left ("Bunu hatırla" refers to something said before).
    public static func fact(from command: String) -> String? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        var kept: [String] = []
        var previous = ""
        for token in tokens {
            let word = TurkishText.folded(token)
            let isRequest = rememberWords.contains(word) || fillerWords.contains(word)
                || (word == "istiyorum" && previous == "hatirlamani")
                || (["tut", "olsun", "tutar"].contains(word) && previous == "aklinda")
                || (word == "aklinda" && tokens.count > 1)
            if !isRequest, !word.isEmpty { kept.append(token) }
            if !word.isEmpty { previous = word }
        }
        let fact = kept.joined(separator: " ").trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return fact.isEmpty ? nil : fact
    }

    private static func containsPhrase(_ words: [String], _ first: String, _ seconds: Set<String>) -> Bool {
        zip(words, words.dropFirst()).contains { $0 == first && seconds.contains($1) }
    }
}
