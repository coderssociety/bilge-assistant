/// English counterpart of `MemoryIntent`. "Remember" (store a fact) and "remind" (a reminder) look alike,
/// so the router model is not trusted with either.
enum EnglishMemoryIntent {
    private static let questionWords: Set<String> = ["what", "whats", "which", "anything", "show", "list", "tell"]
    private static let clearVerbs: Set<String> = ["clear", "erase", "wipe", "reset", "delete", "empty"]
    private static let requestWords: Set<String> = ["please", "can", "could", "you", "would"]
    private static let forgetFillers: Set<String> = [
        "forget", "about", "the", "that", "thing", "info", "information", "fact", "what", "i", "told", "you", "said",
        "please", "now", "can", "could", "would",
    ]
    private static let referenceWords: Set<String> = ["this", "that", "it"]

    static func parse(_ command: String) -> MemoryIntent? {
        let words = words(command)
        if words.contains(where: { $0.hasPrefix("remind") }) { return nil }
        let mentionsMemory = words.contains { $0 == "memory" || $0 == "memories" }
        let asks = words.contains(where: questionWords.contains)
        if (words.contains("remember") && asks) || containsSequence(words, ["know", "about", "me"])
            || (mentionsMemory && asks) {
            return .list
        }
        if containsSequence(words, ["dont", "forget"]) || containsSequence(words, ["do", "not", "forget"]) { return .remember }
        if words.contains("forget") || (mentionsMemory && words.contains(where: clearVerbs.contains)) { return .forget }
        if words.contains("remember") || containsSequence(words, ["keep", "in", "mind"]) { return .remember }
        return nil
    }

    /// "Forget everything" → all, "Forget that" → the latest fact, "Forget my coffee order" → "my coffee order".
    static func forgetTarget(from command: String) -> MemoryIntent.ForgetTarget {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        let words = tokens.map { TurkishText.folded($0) }
        let clearsMemory = words.contains { $0 == "memory" } && words.contains(where: clearVerbs.contains)
        if clearsMemory || words.contains("everything") || containsSequence(words, ["it", "all"]) { return .all }
        let kept = zip(tokens, words).filter { _, word in
            !word.isEmpty && !forgetFillers.contains(word) && !referenceWords.contains(word)
        }
        let query = kept.map(\.0).joined(separator: " ").trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return query.isEmpty ? .latest : .matching(query)
    }

    /// "Remember that the door code changed" → "the door code changed"; nil for "remember this".
    static func fact(from command: String) -> String? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        let words = tokens.map { TurkishText.folded($0) }
        guard let start = requestEnd(in: words) else { return nil }
        var kept = Array(tokens[start...])
        if let first = kept.first, ["that", "this"].contains(TurkishText.folded(first)), kept.count > 1 { kept.removeFirst() }
        let fact = kept.joined(separator: " ").trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        guard !fact.isEmpty, !referenceWords.contains(TurkishText.folded(fact)) else { return nil }
        return fact
    }

    /// Index just past "please remember", "don't forget", "keep in mind" and the like.
    private static func requestEnd(in words: [String]) -> Int? {
        let phrases: [[String]] = [["dont", "forget"], ["do", "not", "forget"], ["keep", "in", "mind"], ["remember"]]
        for phrase in phrases {
            guard let index = sequenceIndex(words, phrase) else { continue }
            let before = words[..<index]
            guard before.allSatisfy(requestWords.contains) else { continue }
            return index + phrase.count
        }
        return nil
    }

    private static func words(_ command: String) -> [String] {
        TurkishText.folded(command).split(separator: " ").map(String.init)
    }

    private static func containsSequence(_ words: [String], _ sequence: [String]) -> Bool {
        sequenceIndex(words, sequence) != nil
    }

    private static func sequenceIndex(_ words: [String], _ sequence: [String]) -> Int? {
        guard words.count >= sequence.count else { return nil }
        return (0...(words.count - sequence.count)).first { Array(words[$0..<$0 + sequence.count]) == sequence }
    }
}
