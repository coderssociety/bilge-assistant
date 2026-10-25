/// Which timer a cancel request means ("çay zamanlayıcısını iptal et", "ikinci alarmı sil",
/// "zamanlayıcıyı kapat", "bütün alarmları sil"), so a request about one never cancels them all.
/// Expects digitized text ("2'nci").
public enum TimerTarget: Sendable, Equatable {
    case all
    case label(String)
    /// 1-based in fire order; negative counts from the end ("son" → -1).
    case position(Int)
    /// One timer, without saying which.
    case any

    public enum Selection: Sendable, Equatable { case timer(Int), noMatch, ambiguous }

    private struct Words {
        let cancelVerbs: Set<String>
        let allWords: Set<String>
        let subjects: [String]
        let pluralMarker: String
        let ordinals: [String: Int]
        let ordinalSuffixes: Set<String>
        let fillers: Set<String>
    }

    private static let turkish = Words(
        cancelVerbs: ["iptal", "sil", "kapat", "durdur", "kaldir", "sustur"],
        allWords: ["hepsini", "hepsi", "tumunu", "tum", "butun", "tamamini"],
        subjects: ["zamanlayici", "alarm"],
        pluralMarker: "lar",
        ordinals: ["ilk": 1, "birinci": 1, "son": -1, "sonuncu": -1, "sonuncuyu": -1],
        ordinalSuffixes: ["inci", "nci", "uncu", "ncu"],
        fillers: ["bu", "su", "o", "benim", "kurdugum", "kurulan", "kurulu", "icin", "olan", "lutfen", "simdi", "hemen"])

    private static let english = Words(
        cancelVerbs: ["cancel", "stop", "delete", "remove", "clear", "off", "kill"],
        allWords: ["all", "every", "everything"],
        subjects: ["timer", "alarm"],
        pluralMarker: "s",
        ordinals: ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "last": -1],
        ordinalSuffixes: ["st", "nd", "rd", "th"],
        fillers: ["the", "my", "this", "that", "a", "please", "for", "cancel", "stop", "delete", "remove", "clear",
                  "turn", "off", "kill", "set", "you", "can", "could"])

    /// Nil unless the request asks to cancel something.
    public static func parse(_ text: String, language: AssistantLanguage = .turkish) -> TimerTarget? {
        let vocabulary = language == .english ? english : turkish
        let words = TurkishText.folded(text).split(separator: " ").map(String.init)
        guard words.contains(where: vocabulary.cancelVerbs.contains) else { return nil }
        if words.contains(where: vocabulary.allWords.contains) { return .all }
        guard let subjectIndex = words.firstIndex(where: { word in vocabulary.subjects.contains(where: word.hasPrefix) })
        else { return .any }
        let subject = words[subjectIndex]
        let stem = vocabulary.subjects.first(where: subject.hasPrefix) ?? ""
        if subject.dropFirst(stem.count).hasPrefix(vocabulary.pluralMarker) { return .all }
        var described = Array(words[..<subjectIndex])
        if language == .english, described.allSatisfy(vocabulary.fillers.contains),
           let forIndex = words[subjectIndex...].firstIndex(of: "for") {
            described = Array(words[(forIndex + 1)...])
        }
        if let position = described.lazy.compactMap({ ordinal($0, in: vocabulary) }).first { return .position(position) }
        let label = described.filter { !vocabulary.fillers.contains($0) && !vocabulary.cancelVerbs.contains($0) }
        return label.isEmpty ? .any : .label(label.joined(separator: " "))
    }

    /// `labels` are the running timers' labels in fire order.
    public static func select(_ target: TimerTarget, labels: [String?]) -> Selection {
        switch target {
        case .all, .any:
            if labels.count == 1 { return .timer(0) }
            return labels.isEmpty ? .noMatch : .ambiguous
        case let .position(position):
            let index = position < 0 ? labels.count + position : position - 1
            return labels.indices.contains(index) ? .timer(index) : .noMatch
        case let .label(query):
            let wanted = TurkishText.folded(query)
            let matches = labels.indices.filter { index in
                guard let label = labels[index].map(TurkishText.folded), !label.isEmpty, !wanted.isEmpty else { return false }
                return label.contains(wanted) || wanted.contains(label)
            }
            if matches.count == 1 { return .timer(matches[0]) }
            return matches.isEmpty ? .noMatch : .ambiguous
        }
    }

    private static func ordinal(_ word: String, in vocabulary: Words) -> Int? {
        if let named = vocabulary.ordinals[word] { return named }
        let digits = word.prefix(while: \.isNumber)
        guard !digits.isEmpty, vocabulary.ordinalSuffixes.contains(String(word.dropFirst(digits.count))) else { return nil }
        return Int(digits)
    }
}
