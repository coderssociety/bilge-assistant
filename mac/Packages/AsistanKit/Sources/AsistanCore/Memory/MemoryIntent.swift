/// Recognizes requests about the assistant's memory without the model. "Hatırla" (remember) and
/// "hatırlat" (remind) differ by one letter, and the router model cannot be trusted to tell them apart.
public enum MemoryIntent: Equatable, Sendable {
    case remember, forget, list

    public enum ForgetTarget: Equatable, Sendable {
        case all, latest
        case matching(String)
    }

    private static let dontForgetWords: Set<String> = ["unutma", "unutmayin", "unutmasana"]
    private static let rememberWords: Set<String> = dontForgetWords.union(["hatirla", "hatirlasana", "hatirlayin", "hatirlamani"])
    private static let forgetWords: Set<String> = ["unut", "unutsana", "unutun", "unutur"]
    private static let clearVerbs: Set<String> = ["sil", "temizle", "bosalt", "sifirla"]
    private static let questionWords: Set<String> = ["ne", "neler", "neleri", "nedir"]
    private static let fillerWords: Set<String> = ["sunu", "bunu", "lutfen"]
    private static let forgetFillers: Set<String> = [
        "ilgili", "hakkindaki", "bilgiyi", "bilgileri", "bilgi", "kaydi", "seyi", "olan", "musun", "misin", "artik",
    ]

    public static func parse(_ command: String, language: AssistantLanguage = .turkish) -> MemoryIntent? {
        if language == .english { return EnglishMemoryIntent.parse(command) }
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        if words.contains(where: { $0.hasPrefix("hatirlat") }) { return nil }
        // "Hafızanda", "hafızanı": the assistant's; "Mac'in hafızası ne kadar dolu" asks about the computer.
        let mentionsMemory = words.contains { $0.hasPrefix("hafizan") || $0.hasPrefix("hafizada") }
        let asks = words.contains(where: questionWords.contains)
        if (words.contains("hatirliyorsun") && asks) || (words.contains("hakkimda") && words.contains("biliyorsun"))
            || (mentionsMemory && asks) {
            return .list
        }
        if words.contains(where: forgetWords.contains) || (mentionsMemory && words.contains(where: clearVerbs.contains)) {
            return .forget
        }
        if isReminder(words) { return nil }
        if words.contains(where: rememberWords.contains) || containsPhrase(words, "aklinda", ["tut", "olsun", "tutar"]) {
            return .remember
        }
        return nil
    }

    /// "Her şeyi unut" → all, "Bunu unut" → the latest fact, "Kahveyle ilgili bilgiyi unut" → "Kahveyle".
    public static func forgetTarget(from command: String, language: AssistantLanguage = .turkish) -> ForgetTarget {
        if language == .english { return EnglishMemoryIntent.forgetTarget(from: command) }
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
    public static func fact(from command: String, language: AssistantLanguage = .turkish) -> String? {
        if language == .english { return EnglishMemoryIntent.fact(from: command) }
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

    /// Where a fact says "-dığını" or "-acağını": "kahvemi şekersiz içtiğimi unutma".
    private static let factEndings = ["digi", "dugu", "tigi", "tugu", "acagi", "ecegi"]
    private static let timeWords = [
        "bugun", "yarin", "aksam", "sabah", "ogle", "gece", "hafta", "pazartesi", "sali", "carsamba", "persembe", "cuma",
        "pazar", "saat", "dakika",
    ]

    /// "Yarın toplantıyı unutma", "ilacımı içmeyi unutma": something to be reminded of, not a fact to keep.
    private static func isReminder(_ words: [String]) -> Bool {
        guard let index = words.firstIndex(where: dontForgetWords.contains) else { return false }
        let object = index > 0 ? words[index - 1] : ""
        if fillerWords.contains(object) || factEndings.contains(where: object.contains) { return false }
        if object.hasSuffix("mayi") || object.hasSuffix("meyi") { return true }
        return words.contains { word in timeWords.contains(where: word.hasPrefix) }
    }

    private static func containsPhrase(_ words: [String], _ first: String, _ seconds: Set<String>) -> Bool {
        zip(words, words.dropFirst()).contains { $0 == first && seconds.contains($1) }
    }
}
