/// Spoken controls inside dictation. Only whole utterances count, so a sentence that merely contains
/// "sil" or "satır" is typed as text.
public enum DictationCommand: Equatable, Sendable {
    case newLine, newParagraph, deleteLast, finish

    private static let phrases: [String: DictationCommand] = [
        "yeni satir": .newLine, "alt satir": .newLine, "alt satira gec": .newLine, "satir atla": .newLine,
        "yeni paragraf": .newParagraph, "paragraf": .newParagraph,
        "son cumleyi sil": .deleteLast, "sonuncuyu sil": .deleteLast, "geri al": .deleteLast, "onu sil": .deleteLast,
        "sonu sil": .deleteLast, "son yazdigini sil": .deleteLast,
        "dikteyi bitir": .finish, "dikte bitti": .finish, "tamam bitti": .finish, "dikteyi kapat": .finish,
        "dikte modunu kapat": .finish, "yazmayi bitir": .finish, "bitti": .finish,
        "dikteyi durdur": .finish, "dikteyi sonlandir": .finish, "dikteyi kes": .finish, "dikte modunu bitir": .finish,
        "dikte modunu durdur": .finish, "dikteden cik": .finish, "dikte modundan cik": .finish,
        "yazmayi birak": .finish, "yazmayi durdur": .finish, "yazmayi kes": .finish,
    ]
    /// Said around a command ("dikteyi bitir lütfen"); without them the command would be typed as text.
    private static let politeness: Set<String> = ["lutfen", "artik", "hemen", "simdi"]

    private static let englishPhrases: [String: DictationCommand] = [
        "new line": .newLine, "next line": .newLine, "line break": .newLine,
        "new paragraph": .newParagraph, "next paragraph": .newParagraph,
        "delete that": .deleteLast, "scratch that": .deleteLast, "delete the last sentence": .deleteLast,
        "delete last sentence": .deleteLast, "undo that": .deleteLast, "remove that": .deleteLast,
        "stop dictation": .finish, "end dictation": .finish, "finish dictation": .finish, "dictation off": .finish,
        "stop dictating": .finish, "im done": .finish, "done": .finish, "turn off dictation": .finish,
        "turn dictation off": .finish, "disable dictation": .finish, "dictation mode off": .finish,
        "stop typing": .finish, "stop writing": .finish, "exit dictation": .finish, "quit dictation": .finish,
    ]
    private static let englishPoliteness: Set<String> = ["please", "now", "ok", "okay"]

    public static func parse(_ text: String, language: AssistantLanguage = .turkish) -> DictationCommand? {
        let (table, polite) = language == .english ? (englishPhrases, englishPoliteness) : (phrases, politeness)
        var words = TurkishText.folded(text).split(separator: " ").map(String.init)
        while words.count > 1, let first = words.first, polite.contains(first) { words.removeFirst() }
        while words.count > 1, let last = words.last, polite.contains(last) { words.removeLast() }
        return table[words.joined(separator: " ")]
    }

    /// "Dikte modunu başlat", "dikteye başla", "yazdırmaya başla"; "start dictation", "dictate".
    public static func isStart(_ text: String, language: AssistantLanguage = .turkish) -> Bool {
        if language == .english {
            let words = TurkishText.folded(text).split(separator: " ").map(String.init)
            let mentions = words.contains { $0.hasPrefix("dictat") }
            let starts = words.contains { ["start", "begin", "turn", "enable", "take"].contains($0) } || words.first == "dictate"
            let stops = words.contains { ["off", "stop", "end", "disable", "finish"].contains($0) }
            return mentions && starts && !stops
        }
        let words = TurkishText.folded(text).split(separator: " ").map(String.init)
        let mentions = words.contains { $0.hasPrefix("dikte") || $0.hasPrefix("yazdirma") }
        let starts = words.contains { $0.hasPrefix("basla") || $0.hasPrefix("baslat") || $0 == "ac" }
        return mentions && starts
    }
}
