/// "Bunu özetle", "bu sayfayı çevir", "şu dosyayı aç": a request about something on screen, recognized
/// by a pointing word together with what to do with it.
public struct ContextIntent: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case summarize, translate, explain, read, open
    }

    public enum Kind: Equatable, Sendable {
        case text, file, page, document
    }

    public let action: Action
    public let wanted: Kind?

    public init(action: Action, wanted: Kind?) {
        self.action = action
        self.wanted = wanted
    }

    private static let pointingWords: Set<String> = [
        "bu", "bunu", "buna", "bunun", "bunlari", "su", "sunu", "suna", "sunun", "secili", "secilen", "sectigim",
        "isaretledigim", "isaretli", "acik", "ondeki",
    ]
    private static let kindPrefixes: [(String, Kind)] = [
        ("metn", .text), ("metin", .text), ("yazi", .text), ("paragraf", .text), ("cumle", .text),
        ("dosya", .file), ("belge", .document), ("dokuman", .document), ("pdf", .document),
        ("sayfa", .page), ("site", .page), ("link", .page), ("baglanti", .page), ("makale", .page), ("haber", .page),
    ]
    private static let actionPrefixes: [(String, Action)] = [
        ("ozetle", .summarize), ("ozet", .summarize), ("cevir", .translate), ("acikla", .explain), ("anlat", .explain),
        ("ne demek", .explain), ("oku", .read), ("ne yaziyor", .read), ("ac", .open),
    ]
    /// Words that point at something else than the screen: "bu akşam", "bu şarkı".
    private static let otherReferents = ["aksam", "sabah", "gece", "hafta", "ay", "yil", "sarki", "parca", "sefer", "kez"]

    public static func parse(_ command: String) -> ContextIntent? {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        guard let pointer = words.firstIndex(where: pointingWords.contains) else { return nil }
        if words.indices.contains(pointer + 1), otherReferents.contains(where: words[pointer + 1].hasPrefix) { return nil }
        let wanted = words.lazy.compactMap { word in kindPrefixes.first { word.hasPrefix($0.0) }?.1 }.first
            ?? (words.contains { ["secili", "secilen", "sectigim", "isaretledigim", "isaretli"].contains($0) } ? .text : nil)
        let text = words.joined(separator: " ")
        guard let action = actionPrefixes.first(where: { prefix, _ in
            prefix.contains(" ") ? text.contains(prefix) : words.contains { word in word == prefix || (word.hasPrefix(prefix) && prefix.count > 2) }
        })?.1 else { return nil }
        return ContextIntent(action: action, wanted: wanted)
    }

    /// Whether the command points at something ("bunu", "şu dosya"), so the screen is worth reading.
    public static func points(_ command: String) -> Bool {
        let words = TurkishText.folded(command).split(separator: " ").map(String.init)
        return words.indices.contains { index in
            pointingWords.contains(words[index])
                && !(words.indices.contains(index + 1) && otherReferents.contains(where: words[index + 1].hasPrefix))
        }
    }

    /// The kind a pointing phrase names: "bu linki" → page, "şu dosyayı" → file.
    public static func wantedKind(in text: String) -> Kind? {
        TurkishText.folded(text).split(separator: " ").lazy.compactMap { word in kindPrefixes.first { word.hasPrefix($0.0) }?.1 }.first
    }

    /// A message body that only points at the screen ("bunu", "bu linki") rather than saying something.
    public static func onlyPoints(_ text: String) -> Bool {
        let words = TurkishText.folded(text).split(separator: " ").map(String.init)
        guard let first = words.first else { return true }
        guard pointingWords.contains(first), words.count <= 2 else { return false }
        return words.count == 1 || kindPrefixes.contains { words[1].hasPrefix($0.0) }
    }
}
