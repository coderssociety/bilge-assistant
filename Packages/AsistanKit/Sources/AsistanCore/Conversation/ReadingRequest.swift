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
}
