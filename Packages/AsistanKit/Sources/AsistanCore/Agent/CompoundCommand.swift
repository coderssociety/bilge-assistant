/// Splits "Safari'yi aç ve sesi yüzde 30 yap" into separate commands. Plain "ve" only splits after
/// a known imperative, so "kahve ve süt almayı hatırlat" or "Ali ve Veli'ye yaz" stay whole.
public enum CompoundCommand {
    private static let sequenceMarkers: [[String]] = [["ve", "sonra"], ["sonra", "da"], ["daha", "sonra"], ["ardindan"], ["ayrica"], ["bir", "de"]]
    private static let imperatives: Set<String> = [
        "ac", "kapat", "yap", "ekle", "gonder", "at", "yaz", "oku", "cal", "kur", "bul", "soyle", "al", "ara", "goster",
        "durdur", "kilitle", "gizle", "olustur", "hatirlat", "sil", "kopyala", "ozetle", "cevir", "tamamla", "isaretle",
        "baslat", "degistir", "ayarla", "artir", "azalt", "kis", "getir", "git", "bak", "anlat", "kucult", "tasi", "kaydet",
        "cek", "gec", "yolla", "sor", "hesapla", "listele", "kontrol", "et",
    ]
    private static let minimumPartWords = 2

    private static let englishMarkers: [[String]] = [["and", "then"], ["then"], ["after", "that"], ["and", "also"], ["also"]]
    /// English verbs come first, so plain "and" splits only before one: "open Safari and set the volume…",
    /// while "call Ali and Veli" or "remind me to buy milk and bread" stay whole.
    private static let englishImperatives: Set<String> = [
        "open", "close", "quit", "set", "add", "send", "text", "email", "message", "write", "read", "play", "find",
        "tell", "show", "stop", "pause", "lock", "hide", "create", "make", "remind", "delete", "copy", "summarize",
        "translate", "mark", "start", "change", "turn", "increase", "decrease", "bring", "go", "look", "move", "save",
        "take", "switch", "ask", "calculate", "list", "check", "search", "put", "type", "call", "note",
    ]
    private static let englishReferences: Set<String> = [
        "him", "her", "them", "it", "that", "this", "there", "summary", "result", "results", "same", "its", "their",
    ]

    public static func split(_ text: String, language: AssistantLanguage = .turkish) -> [String]? {
        if language == .english { return splitEnglish(text) }
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let folded = tokens.map { TurkishText.folded($0) }
        var parts: [[String]] = []
        var current: [String] = []
        var index = 0
        while index < tokens.count {
            if let marker = marker(at: index, in: folded, after: current) {
                parts.append(current)
                current = []
                index += marker
                continue
            }
            current.append(tokens[index])
            index += 1
        }
        parts.append(current)
        let commands = parts.map { $0.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) }
        guard commands.count >= 2, commands.allSatisfy({ $0.split(separator: " ").count >= minimumPartWords }) else { return nil }
        return commands
    }

    private static let references: Set<String> = [
        "ona", "onu", "onun", "ondan", "onlara", "onlari", "bunu", "buna", "bunun", "bundan", "sunu", "oraya", "orada",
        "ozeti", "ozetini", "ozetle", "sonucu", "sonucunu", "aynisini", "bulduğun", "buldugun", "bulduklarini", "icerigini",
        "numarasina", "adresine", "metni", "metnini",
    ]

    /// True when a later part refers to an earlier one's result ("Ahmet'in numarasını bul ve ona mesaj at",
    /// "PDF'i özetle ve özeti panoya kopyala"); such requests need planning, the others can run one by one.
    public static func hasDependentParts(_ parts: [String], language: AssistantLanguage = .turkish) -> Bool {
        let words = language == .english ? englishReferences : references
        return parts.dropFirst().contains { part in
            TurkishText.folded(part).split(separator: " ").contains { words.contains(String($0)) }
        }
    }

    /// Requests whose content may itself contain "and <verb>": "remind me to call the bank and send the invoice".
    private static let englishWholeRequests: Set<String> = ["remind", "note", "text", "email", "message", "tell", "write"]

    private static func splitEnglish(_ text: String) -> [String]? {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let folded = tokens.map { TurkishText.folded($0) }
        let plainAndSplits = !folded.prefix(2).contains(where: englishWholeRequests.contains)
        var parts: [[String]] = []
        var current: [String] = []
        var index = 0
        while index < tokens.count {
            if !current.isEmpty, let length = englishMarker(at: index, in: folded, plainAnd: plainAndSplits) {
                parts.append(current)
                current = []
                index += length
                continue
            }
            current.append(tokens[index])
            index += 1
        }
        parts.append(current)
        let commands = parts.map { $0.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) }
        guard commands.count >= 2, commands.allSatisfy({ $0.split(separator: " ").count >= minimumPartWords }) else { return nil }
        return commands
    }

    private static func englishMarker(at index: Int, in folded: [String], plainAnd: Bool) -> Int? {
        for marker in englishMarkers where Array(folded[index..<min(index + marker.count, folded.count)]) == marker {
            return marker.count
        }
        if plainAnd, folded[index] == "and", index + 1 < folded.count, englishImperatives.contains(folded[index + 1]) { return 1 }
        return nil
    }

    /// Length of the separator starting at `index`, or nil when there is none there.
    private static func marker(at index: Int, in folded: [String], after current: [String]) -> Int? {
        guard !current.isEmpty else { return nil }
        for marker in sequenceMarkers where Array(folded[index..<min(index + marker.count, folded.count)]) == marker {
            return marker.count
        }
        let previous = TurkishText.folded(current.last ?? "").trimmingCharacters(in: .punctuationCharacters)
        if folded[index] == "ve", imperatives.contains(previous) { return 1 }
        return nil
    }
}
