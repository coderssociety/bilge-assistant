/// English counterpart of `ContextIntent`'s Turkish words: "summarize this", "translate the selected text",
/// "send this to Ahmet".
enum EnglishContextWords {
    private static let pointingWords: Set<String> = ["this", "that", "these", "those", "selected", "highlighted", "current"]
    /// Words after a pointer that name something other than the screen: "this evening", "this song".
    private static let otherReferents: Set<String> = [
        "morning", "afternoon", "evening", "night", "week", "weekend", "month", "year", "song", "track", "time", "one",
        "is", "was", "will", "would", "should", "could",
    ]
    private static let kinds: [String: ContextIntent.Kind] = [
        "text": .text, "paragraph": .text, "sentence": .text, "passage": .text, "selection": .text,
        "file": .file, "document": .document, "doc": .document, "pdf": .document, "report": .document,
        "page": .page, "site": .page, "website": .page, "link": .page, "article": .page, "tab": .page,
    ]
    private static let actions: [(words: Set<String>, action: ContextIntent.Action)] = [
        (["summarize", "summarise", "summary", "sum", "tldr"], .summarize),
        (["translate", "translation"], .translate),
        (["explain", "mean", "means"], .explain),
        (["read"], .read),
        (["open"], .open),
    ]
    private static let selectionWords: Set<String> = ["selected", "highlighted"]
    /// Verbs that take what is on screen as their object: "send this", "summarize that".
    private static let objectVerbs: Set<String> = [
        "send", "share", "email", "text", "message", "copy", "summarize", "summarise", "translate", "explain", "read",
        "open", "save", "forward", "attach", "show",
    ]
    /// Requests about later or about memory, where "this" is not the screen: "remind me to read this".
    private static let laterWords: Set<String> = ["remind", "remember", "note"]

    static func parse(_ command: String) -> ContextIntent? {
        let words = words(command)
        guard !words.contains(where: laterWords.contains), pointingIndex(in: words) != nil else { return nil }
        guard let action = actions.first(where: { !$0.words.isDisjoint(with: words) })?.action else { return nil }
        let wanted = kind(in: words) ?? (words.contains(where: selectionWords.contains) ? .text : nil)
        return ContextIntent(action: action, wanted: wanted)
    }

    /// Only when the pointer is the object ("send this", "this link"), not "tell Ali that…".
    static func points(_ command: String) -> Bool {
        let words = words(command)
        if parse(command) != nil { return true }
        return words.indices.contains { index in
            guard pointingWords.contains(words[index]), !isOtherReferent(after: index, in: words) else { return false }
            let named = index + 1 < words.count && kind(in: [words[index + 1]]) != nil
            let object = index > 0 && objectVerbs.contains(words[index - 1])
            return named || object
        }
    }

    static func wantedKind(in text: String) -> ContextIntent.Kind? {
        kind(in: words(text))
    }

    /// "this", "that link": a message body that points at the screen instead of saying something.
    static func onlyPoints(_ text: String) -> Bool {
        let words = words(text).filter { $0 != "the" }
        guard let first = words.first else { return true }
        guard pointingWords.contains(first), words.count <= 2 else { return false }
        return words.count == 1 || kinds[words[1]] != nil
    }

    private static func pointingIndex(in words: [String]) -> Int? {
        words.indices.first { index in pointingWords.contains(words[index]) && !isOtherReferent(after: index, in: words) }
    }

    /// "this evening's", "that song": prefixes, so possessives and plurals count too.
    private static func isOtherReferent(after index: Int, in words: [String]) -> Bool {
        index + 1 < words.count && otherReferents.contains { words[index + 1].hasPrefix($0) }
    }

    private static func kind(in words: [String]) -> ContextIntent.Kind? {
        words.lazy.compactMap { kinds[$0] ?? kinds[String($0.dropLast())] }.first
    }

    private static func words(_ text: String) -> [String] {
        TurkishText.folded(text).split(separator: " ").map(String.init)
    }
}
