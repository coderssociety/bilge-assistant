/// macOS has no public API that turns a Focus on or off, but a user's Shortcut with the "Set Focus"
/// action does it. This picks that shortcut by name: one meant for the asked direction ("Rahatsız Etme
/// Aç"), else one without a direction (a toggle), preferring a name that shares the command's words
/// ("Uyku odağını aç" → "Uyku Odağı Aç").
public enum FocusShortcut {
    private static let focusStems = ["rahatsiz", "odak", "odag", "focus", "dnd", "disturb"]
    private static let onWords: Set<String> = ["ac", "acik", "on", "baslat", "etkinlestir", "aktif", "enable", "start"]
    private static let offStems = ["kapat", "kapali", "off", "bitir", "sonlandir", "disable", "stop"]
    private static let ignoredWords: Set<String> = ["modu", "modunu", "mode", "turn", "the", "etme", "etmeyi", "etmeyin", "not", "do", "lutfen"]

    private enum Direction { case on, off, toggle }

    public static func pick(from names: [String], turnOn: Bool, command: String) -> String? {
        let asked = Set(words(command).filter { word in !isFocusWord(word) && !ignoredWords.contains(word) && direction(of: [word]) == .toggle })
        let candidates = names.compactMap { name -> (name: String, score: Int)? in
            let nameWords = words(name)
            guard nameWords.contains(where: isFocusWord) else { return nil }
            let direction = direction(of: nameWords)
            guard direction == .toggle || (direction == .on) == turnOn else { return nil }
            let shared = asked.intersection(nameWords).count
            return (name, shared * 2 + (direction == .toggle ? 0 : 1))
        }
        return candidates.max { $0.score < $1.score }?.name
    }

    private static func isFocusWord(_ word: String) -> Bool {
        focusStems.contains(where: word.hasPrefix)
    }

    private static func direction(of words: [String]) -> Direction {
        if words.contains(where: { word in offStems.contains(where: word.hasPrefix) }) { return .off }
        return words.contains(where: onWords.contains) ? .on : .toggle
    }

    private static func words(_ text: String) -> [String] {
        TurkishText.folded(text).split(separator: " ").map(String.init)
    }
}
