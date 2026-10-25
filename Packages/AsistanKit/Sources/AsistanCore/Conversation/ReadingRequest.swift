/// What a follow-up asks of the text just read.
public enum ReadingRequest {
    private static let continuationStems = ["devam", "sonras", "sonraki", "kalan", "geris", "digerler", "baska"]
    private static let continuationFillers: Set<String> = [
        "oku", "okur", "okusana", "okuyabilir", "okuyun", "okumaya", "et", "eder", "etsene", "edebilir", "edin", "musun",
        "misin", "mi", "var", "ne", "neler", "yaziyor", "lutfen", "hadi", "peki", "tamam", "evet", "de", "da", "bir",
        "kismi", "kismini", "kisim", "sayfa", "sayfayi", "bolum", "bolumu", "anlat", "soyle", "listele", "kaldigin",
        "yerden",
    ]
    private static let englishContinuationWords: Set<String> = [
        "continue", "more", "rest", "remaining", "next", "on", "going", "reading",
    ]
    private static let englishContinuationFillers: Set<String> = [
        "read", "the", "please", "go", "keep", "carry", "part", "page", "section", "what", "whats", "is", "there", "any",
        "tell", "me", "show", "and", "ok", "okay", "then", "so", "can", "could", "you", "it", "of", "say", "list", "a",
        "bit", "yes", "from", "where", "left", "off",
    ]

    /// "Devamını oku", "devam et", "sonrası", "gerisi"; "read more", "continue", "go on", "what's next".
    /// Only the whole command counts, so "müziğe devam et" or "next song" stay commands of their own.
    public static func isContinuation(_ command: String, language: AssistantLanguage = .turkish) -> Bool {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return false }
        if language == .english {
            return words.contains(where: englishContinuationWords.contains)
                && words.allSatisfy { englishContinuationWords.contains($0) || englishContinuationFillers.contains($0) }
        }
        let isContinuationWord = { (word: String) in continuationStems.contains(where: word.hasPrefix) }
        return words.contains(where: isContinuationWord)
            && words.allSatisfy { isContinuationWord($0) || continuationFillers.contains($0) }
    }

    private static let textNouns = [
        "madde", "paragraf", "bolum", "kisim", "kism", "cumle", "satir", "metin", "metn", "belge", "sayfa", "makale",
        "liste", "baslik", "baslig", "etkinlik", "etkinlig",
    ]
    /// Not a stem: "yazın" is also "in summer".
    private static let writingNouns: Set<String> = ["yazi", "yaziyi", "yazida", "yazidaki", "yazinin"]
    private static let pointers: Set<String> = [
        "bu", "su", "bunu", "bunun", "buna", "bunda", "bundaki", "bundan", "sunu", "sunun", "onu", "onun", "ona",
        "orada", "oradaki", "burada", "buradaki",
    ]
    private static let ordinals = ["ilk", "birinci", "ikinci", "ucuncu", "dorduncu", "besinci", "altinci", "sonuncu"]
    private static let textVerbs = [
        "kisalt", "ozetle", "acikla", "sadelestir", "basitlestir", "cevir", "anlat", "yorumla", "anlami", "demek",
    ]
    private static let verbFillers: Set<String> = [
        "daha", "biraz", "kisaca", "kisa", "lutfen", "misin", "musun", "bir", "de", "da", "tekrar", "simdi", "hadi",
        "peki", "bana",
    ]
    private static let englishTextNouns: Set<String> = [
        "point", "points", "item", "items", "bullet", "paragraph", "section", "part", "sentence", "line", "text",
        "document", "page", "article", "list", "passage", "heading", "event", "events",
    ]
    private static let englishPointers: Set<String> = [
        "it", "this", "that", "these", "those", "first", "second", "third", "fourth", "fifth", "last",
    ]
    private static let englishTextVerbs: Set<String> = [
        "shorten", "summarize", "summarise", "simplify", "explain", "translate", "rephrase", "mean", "means", "shorter",
        "simpler",
    ]
    private static let englishVerbFillers: Set<String> = [
        "please", "more", "a", "bit", "briefly", "again", "now", "can", "you", "could", "in", "short", "for", "me",
    ]

    /// "İkinci maddeyi açıkla", "bunu kısalt", "bu ne demek", "özetle"; "explain the second point", "shorten it".
    /// A question that only shares a word with such requests ("bu akşam ne yapsam", "aşk ne demek") does not count.
    public static func refersToReading(_ command: String, language: AssistantLanguage = .turkish) -> Bool {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return false }
        if language == .english {
            let isVerb = { (word: String) in englishTextVerbs.contains(word) }
            return refers(words, isNoun: englishTextNouns.contains, isPointer: englishPointers.contains,
                          isVerb: isVerb, isFiller: { isVerb($0) || englishVerbFillers.contains($0) || englishPointers.contains($0) })
        }
        let isVerb = { (word: String) in textVerbs.contains(where: word.hasPrefix) }
        return refers(words, isNoun: { word in writingNouns.contains(word) || textNouns.contains(where: word.hasPrefix) },
                      isPointer: { word in pointers.contains(word) || ordinals.contains(where: word.hasPrefix) },
                      isVerb: isVerb, isFiller: { isVerb($0) || verbFillers.contains($0) })
    }

    /// "Panodakini özetle", "seçili metni çevir", "what does it mean": more than reading the text out.
    public static func asksBeyondReading(_ command: String, language: AssistantLanguage = .turkish) -> Bool {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        if language == .english { return words.contains(where: englishTextVerbs.contains) }
        return words.contains { word in textVerbs.contains(where: word.hasPrefix) }
    }

    /// A text noun on its own, a pointer with something to do with the text, or only such a verb.
    private static func refers(_ words: [String], isNoun: (String) -> Bool, isPointer: (String) -> Bool,
                               isVerb: (String) -> Bool, isFiller: (String) -> Bool) -> Bool {
        if words.contains(where: isNoun) { return true }
        guard words.contains(where: isVerb) else { return false }
        return words.contains(where: isPointer) || words.allSatisfy(isFiller)
    }
}
