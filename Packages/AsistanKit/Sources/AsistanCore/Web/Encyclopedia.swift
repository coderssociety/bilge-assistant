import Foundation

/// The subject of a clearly encyclopedic question: "Mustafa Kemal Atatürk kimdir", "fotosentez nedir",
/// "Everest hakkında bilgi ver", "who was Ada Lovelace". Questions about the Mac, the screen, the user or
/// the assistant, comparisons and superlatives ("en yüksek dağ hangisi") are left to the conversation.
public enum EncyclopediaQuestion {
    private static let fillers: Set<String> = ["bana", "peki", "acaba", "bilge", "hey", "simdi", "sey"]
    private static let turkishStopWords: Set<String> = [
        "bu", "su", "o", "bunlar", "sunlar", "onlar", "ben", "sen", "biz", "siz", "benim", "senin", "bizim", "sizin",
        "adin", "adim", "ismin", "ismim", "saat", "tarih", "bugun", "yarin", "dun", "hava", "pil", "sarj", "en", "fark",
        "farki", "arasindaki", "sence", "hangi", "kac", "ne", "neden", "nasil", "niye", "kim", "arti", "eksi", "carpi",
        "bolu", "kere", "yuzde",
    ]
    private static let turkishStopPrefixes = [
        "ekran", "secil", "sectig", "kopyala", "isaretle", "takvim", "sarki", "mail", "posta", "dosya", "belge", "sayfa",
        "pencere", "mesaj", "hatirlat", "alarm",
    ]
    /// Too general to look up on their own: "sorun nedir" is about something just said.
    private static let vagueSubjects: Set<String> = [
        "sorun", "mesele", "durum", "plan", "fikir", "haber", "hal", "olay", "amac", "sebep", "sonuc", "cevap", "yanit",
        "soru", "isim", "ad", "problem", "konu",
    ]
    private static let englishPrefixes = [
        "who is ", "who was ", "who were ", "who are ", "what is ", "what's ", "whats ", "what are ", "what was ",
        "tell me about ", "what do you know about ",
    ]
    private static let englishStopWords: Set<String> = [
        "i", "me", "my", "mine", "you", "your", "yours", "we", "us", "our", "it", "its", "this", "that", "these", "those",
        "he", "she", "him", "her", "his", "they", "them", "their", "there", "here", "today", "tomorrow", "yesterday",
        "time", "date", "day", "weather", "battery", "screen", "song", "news", "up", "new", "wrong", "happening", "going",
        "matter", "next", "left", "of", "between", "difference", "in", "on", "for", "to", "from", "than", "vs", "versus",
        "most", "best", "largest", "biggest", "tallest", "highest", "longest", "oldest", "smallest", "plus", "minus",
        "times", "divided", "percent", "squared",
    ]
    private static let maxWords = 5

    public static func subject(in command: String, language: AssistantLanguage) -> String? {
        let text = command.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "?.!,")))
        return language == .english ? english(text) : turkish(text)
    }

    private static func turkish(_ text: String) -> String? {
        var words = text.split(separator: " ").map(String.init)
        let folded = words.map(TurkishText.folded)
        let count = folded.count
        if let index = folded.firstIndex(of: "hakkinda") {
            let rest = Array(folded[(index + 1)...])
            let asks = rest.first?.hasPrefix("bilgi") == true || rest.first?.hasPrefix("anlat") == true
                || rest.starts(with: ["ne", "biliyorsun"]) || rest.starts(with: ["bana", "bilgi"])
            guard asks else { return nil }
            words = Array(words[..<index])
        } else if let last = folded.last, ["kimdir", "kim", "nedir", "nelerdir"].contains(last) {
            words.removeLast()
        } else if count >= 2, folded[count - 2] == "ne", ["demek", "demektir"].contains(folded[count - 1]) {
            words.removeLast(2)
        } else if folded.suffix(3) == ["ne", "anlama", "gelir"] {
            words.removeLast(3)
        } else {
            return nil
        }
        words.removeAll { fillers.contains(TurkishText.folded($0)) }
        if words.count >= 2, TurkishText.folded(words[words.count - 1]) == "anlami" {
            words.removeLast()
            words[words.count - 1] = withoutSuffix(words[words.count - 1])
        }
        let subjectWords = words.map(TurkishText.folded)
        // "Osmanlı Devleti'nin kurucusu kimdir" asks about something of the subject, which the article may not say.
        guard (1...maxWords).contains(words.count), !words.dropLast().contains(where: isGenitive),
              !subjectWords.contains(where: { word in turkishStopWords.contains(word) || turkishStopPrefixes.contains(where: word.hasPrefix) }),
              !(words.count == 1 && vagueSubjects.contains(subjectWords[0])) else { return nil }
        return words.joined(separator: " ")
    }

    private static func english(_ text: String) -> String? {
        let lower = text.lowercased()
        let subject: Substring
        if lower.hasPrefix("what does "), lower.hasSuffix(" mean") {
            subject = text.dropFirst("what does ".count).dropLast(" mean".count)
        } else if let prefix = englishPrefixes.first(where: lower.hasPrefix) {
            subject = text.dropFirst(prefix.count)
        } else {
            return nil
        }
        var words = subject.split(separator: " ").map(String.init)
        if let first = words.first?.lowercased(), ["a", "an"].contains(first) { words.removeFirst() }
        let lowered = words.map { $0.lowercased() }
        guard (1...maxWords).contains(words.count), !lowered.contains(where: englishStopWords.contains),
              !lowered.contains(where: { $0.hasSuffix("'s") || $0.hasSuffix("’s") }),
              !lowered.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        return words.joined(separator: " ")
    }

    /// "Devleti'nin", "Marşı'nın", "sayısının": the first word of an "X'in Y'si" phrase.
    private static func isGenitive(_ word: String) -> Bool {
        let folded = TurkishText.folded(word)
        if folded.hasSuffix("sinin") || folded.hasSuffix("sunun") { return true }
        guard let apostrophe = word.firstIndex(where: { "'’".contains($0) }) else { return false }
        return ["in", "nin", "un", "nun"].contains(TurkishText.folded(String(word[word.index(after: apostrophe)...])))
    }

    /// "Nirvana'nın" → "Nirvana".
    private static func withoutSuffix(_ word: String) -> String {
        guard let apostrophe = word.firstIndex(where: { "'’".contains($0) }) else { return word }
        return String(word[..<apostrophe])
    }
}

/// Reads Wikipedia's REST page summary and its opensearch title list.
public enum WikipediaParser {
    public struct Page: Equatable, Sendable {
        public let title: String
        public let extract: String
        public let isDisambiguation: Bool
    }

    public static func summary(_ data: Data) -> Page? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = root["title"] as? String else { return nil }
        let extract = (root["extract"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let isDisambiguation = (root["type"] as? String) == "disambiguation"
        guard isDisambiguation || !extract.isEmpty else { return nil }
        return Page(title: title, extract: extract, isDisambiguation: isDisambiguation)
    }

    /// `[query, [titles], [descriptions], [links]]`.
    public static func openSearchTitles(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any], root.count > 1,
              let titles = root[1] as? [String] else { return [] }
        return titles
    }

    /// The path component for a title: spaces as underscores, "/" escaped too ("AC/DC").
    public static func titlePath(_ title: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        let underscored = title.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        return underscored.addingPercentEncoding(withAllowedCharacters: allowed) ?? underscored
    }

    /// The summary for the tool-less session, cut at a sentence end within `maxCharacters`.
    public static func material(_ page: Page, maxCharacters: Int, language: AssistantLanguage) -> String {
        var extract = page.extract
        if extract.count > maxCharacters {
            let cut = extract.prefix(maxCharacters)
            extract = cut.lastIndex(of: ".").map { String(cut[...$0]) } ?? String(cut)
        }
        return "\(language == .english ? "Wikipedia" : "Vikipedi") — \(page.title):\n\(extract)"
    }
}
