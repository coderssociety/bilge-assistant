/// English counterpart of `BrowserCommand`'s Turkish rules: "next tab", "go back", "find price on this page".
/// Tab commands need the word "tab"; history and scrolling are whole fixed phrases, so "volume up",
/// "call me back" or "forward it to Sam" never land here.
enum EnglishBrowserCommand {
    private static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9,
    ]
    private static let switchVerbs: Set<String> = ["switch", "go", "jump", "open", "show"]
    private static let findVerbs: Set<String> = ["find", "search", "look"]
    private static let phrases: [String: BrowserCommand] = [
        "go back": .back, "back": .back, "go back a page": .back, "previous page": .back, "go to the previous page": .back,
        "go forward": .forward, "go forward a page": .forward, "next page": .forward,
        "reload": .reload, "refresh": .reload, "reload the page": .reload, "refresh the page": .reload,
        "reload page": .reload, "refresh page": .reload, "reload this page": .reload, "refresh this page": .reload,
        "scroll down": .scrollDown, "page down": .scrollDown, "scroll down a bit": .scrollDown,
        "scroll up": .scrollUp, "page up": .scrollUp, "scroll up a bit": .scrollUp,
        "go to the top": .top, "scroll to the top": .top, "scroll to top": .top, "go to top": .top,
        "top of the page": .top, "go to the top of the page": .top,
        "go to the bottom": .bottom, "scroll to the bottom": .bottom, "scroll to bottom": .bottom, "go to bottom": .bottom,
        "bottom of the page": .bottom, "go to the bottom of the page": .bottom, "end of the page": .bottom,
    ]

    static func parse(_ text: String) -> BrowserCommand? {
        let words = TurkishText.folded(text).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        if let tabIndex = words.firstIndex(where: { $0 == "tab" || $0 == "tabs" }) {
            return tab(words, at: tabIndex, original: text)
        }
        if let found = find(words, original: text) { return found }
        return phrases[words.filter { $0 != "please" }.joined(separator: " ")]
    }

    private static func tab(_ words: [String], at index: Int, original: String) -> BrowserCommand? {
        if words.contains("reopen") || (words.contains("closed") && !words.contains("close")) { return .reopenTab }
        if words.contains("new") { return .newTab }
        if words.contains("close") { return .closeTab }
        if words.contains("next") { return .nextTab }
        if words.contains("previous") { return .previousTab }
        if let ordinal = words.lazy.compactMap({ ordinals[$0] }).first { return .tab(ordinal) }
        if let number = words.dropFirst(index).lazy.compactMap({ Int($0) }).first, (1...99).contains(number) { return .tab(number) }
        if words.contains("last") { return .lastTab }
        // "Switch to the YouTube tab": the title sits between "to (the)" and "tab".
        guard words.contains(where: switchVerbs.contains), let to = words.firstIndex(of: "to"), to < index else { return nil }
        let originalWords = original.split(whereSeparator: \.isWhitespace).map(String.init)
        guard originalWords.count == words.count else { return nil }
        var start = to + 1
        if start < index, words[start] == "the" { start += 1 }
        let title = originalWords[start..<index].joined(separator: " ")
        return title.isEmpty ? nil : .tabNamed(title)
    }

    /// "Find price on this page", "search for return policy on the page".
    private static func find(_ words: [String], original: String) -> BrowserCommand? {
        guard words.contains("page"), let verb = words.firstIndex(where: findVerbs.contains) else { return nil }
        var start = verb + 1
        if start < words.count, words[start] == "for" { start += 1 }
        guard let end = words.indices.first(where: { $0 > start && (words[$0] == "on" || words[$0] == "in") }) else { return nil }
        let originalWords = original.split(whereSeparator: \.isWhitespace).map(String.init)
        guard originalWords.count == words.count else { return nil }
        var phrase = Array(originalWords[start..<end])
        if let first = phrase.first, ["the", "word"].contains(TurkishText.folded(first)), phrase.count > 1 { phrase.removeFirst() }
        let query = phrase.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return query.isEmpty ? nil : .find(query)
    }
}
