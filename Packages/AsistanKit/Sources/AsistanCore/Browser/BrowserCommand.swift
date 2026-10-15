/// Browser control by voice ("sonraki sekmeye geç", "geri git", "bu sayfada fiyatı ara"), recognized by
/// rules. Tab commands need the word "sekme"; history and scrolling need their own fixed phrases, so
/// "geri al" (undo) or "Safari'yi aç" never land here.
public enum BrowserCommand: Equatable, Sendable {
    case nextTab, previousTab, lastTab, newTab, closeTab, reopenTab
    case tab(Int)
    case tabNamed(String)
    case back, forward, reload
    case scrollDown, scrollUp, top, bottom
    case find(String)

    private static let ordinals: [String: Int] = [
        "ilk": 1, "birinci": 1, "ikinci": 2, "ucuncu": 3, "dorduncu": 4, "besinci": 5, "altinci": 6, "yedinci": 7,
        "sekizinci": 8, "dokuzuncu": 9,
    ]
    private static let apostrophes: Set<Character> = ["'", "’", "‘", "`", "´"]

    public static func parse(_ text: String, language: AssistantLanguage = .turkish) -> BrowserCommand? {
        if language == .english { return EnglishBrowserCommand.parse(text) }
        let words = TurkishText.folded(text).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        func has(_ word: String) -> Bool { words.contains(word) }
        func hasPrefix(_ prefix: String) -> Bool { words.contains { $0.hasPrefix(prefix) } }

        if let tabIndex = words.firstIndex(where: { $0.hasPrefix("sekme") }) {
            return tab(words, at: tabIndex, original: text)
        }
        if let found = find(words, original: text) { return found }
        if has("geri") && (hasPrefix("git") || hasPrefix("don")) && words.count <= 3 { return .back }
        if hasPrefix("onceki") && hasPrefix("sayfa") && words.count <= 4 { return .back }
        if has("ileri") && hasPrefix("git") && words.count <= 3 { return .forward }
        if hasPrefix("yenile") && (words.count == 1 || hasPrefix("sayfa")) { return .reload }
        let goesEnd = has("en") || hasPrefix("sayfanin")
        if goesEnd && (hasPrefix("alt") || hasPrefix("sonu") || (has("en") && hasPrefix("asagi"))) { return .bottom }
        if goesEnd && (hasPrefix("ust") || hasPrefix("basi") || (has("en") && hasPrefix("yukari"))) { return .top }
        let scrolls = hasPrefix("kaydir") || hasPrefix("in") || hasPrefix("cik") || words.count <= 2
        if hasPrefix("asagi") && scrolls && words.count <= 3 { return .scrollDown }
        if hasPrefix("yukari") && scrolls && words.count <= 3 { return .scrollUp }
        return nil
    }

    private static func tab(_ words: [String], at index: Int, original: String) -> BrowserCommand? {
        let rest = Set(words)
        if words.contains(where: { $0.hasPrefix("kapattig") }) { return .reopenTab }
        if rest.contains("yeni") { return .newTab }
        if words.contains(where: { $0.hasPrefix("kapat") }) { return .closeTab }
        if words.contains(where: { $0.hasPrefix("sonraki") }) { return .nextTab }
        if words.contains(where: { $0.hasPrefix("onceki") }) { return .previousTab }
        if let ordinal = words.lazy.compactMap({ ordinals[$0] }).first { return .tab(ordinal) }
        if rest.contains("son") { return .lastTab }
        // "YouTube sekmesine geç": the title is what comes before "sekmesi…".
        let switches = words.contains { $0.hasPrefix("gec") || $0 == "ac" || $0.hasPrefix("don") }
        guard switches, index > 0, words[index].hasPrefix("sekmesi") else { return nil }
        let originalWords = original.split(whereSeparator: \.isWhitespace).map(String.init)
        guard originalWords.count == words.count else { return nil }
        let title = originalWords[..<index].joined(separator: " ")
        return title.isEmpty ? nil : .tabNamed(title)
    }

    /// "Bu sayfada fiyat kelimesini ara", "sayfada iade koşulları'nı bul".
    private static func find(_ words: [String], original: String) -> BrowserCommand? {
        guard let page = words.firstIndex(of: "sayfada"),
              let verb = words.lastIndex(where: { $0 == "ara" || $0 == "bul" }), verb > page + 1 else { return nil }
        let originalWords = original.split(whereSeparator: \.isWhitespace).map(String.init)
        guard originalWords.count == words.count else { return nil }
        var phrase = Array(originalWords[(page + 1)..<verb])
        if let last = phrase.last, ["kelimesini", "sozcugunu", "ifadesini", "yazisini"].contains(TurkishText.folded(last)) {
            phrase.removeLast()
        }
        guard let last = phrase.last else { return nil }
        if let mark = last.firstIndex(where: apostrophes.contains) {
            phrase[phrase.count - 1] = String(last[..<mark])
        }
        let query = phrase.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return query.isEmpty ? nil : .find(query)
    }
}
