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
    ]

    public static func parse(_ text: String) -> DictationCommand? {
        phrases[TurkishText.folded(text)]
    }

    /// "Dikte modunu başlat", "dikteye başla", "yazdırmaya başla".
    public static func isStart(_ text: String) -> Bool {
        let words = TurkishText.folded(text).split(separator: " ").map(String.init)
        let mentions = words.contains { $0.hasPrefix("dikte") || $0.hasPrefix("yazdirma") }
        let starts = words.contains { $0.hasPrefix("basla") || $0.hasPrefix("baslat") || $0 == "ac" }
        return mentions && starts
    }
}
