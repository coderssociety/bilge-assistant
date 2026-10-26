import Foundation

/// English counterpart of `TurkishArithmeticParser`: "15 percent of 240", "48 divided by 6", "3 squared".
/// Recognizers write English numbers as digits, so only digits are read.
public enum EnglishArithmeticParser {
    private static let number = #"(\d+(?:\.\d+)?)"#
    private static let fillers: Set<String> = [
        "what", "whats", "is", "how", "much", "calculate", "equals", "equal", "please", "tell", "me", "the", "answer",
        "can", "you", "work", "out", "do",
    ]
    private static let phrases: [(String, String)] = [
        ("multiplied by", "times"), ("divided by", "over"), ("to the power of", "^"), ("raised to", "^"),
    ]
    private static let operatorWords: [String: String] = [
        "plus": "+", "+": "+", "minus": "-", "-": "-", "times": "*", "x": "*", "×": "*", "*": "*",
        "over": "/", "÷": "/", "/": "/", "^": "^",
    ]
    private static let fractions: [(word: String, divisor: Int)] = [("half", 2), ("quarter", 4), ("third", 3)]

    public static func expression(from command: String) -> String? {
        let text = normalized(command)
        return percentOf(text) ?? fractionOf(text) ?? power(text) ?? operatorChain(text)
    }

    /// True when every number in a model-written expression was said, allowing the 100 of a percentage
    /// and the divisor of "half"/"a third"/"a quarter".
    public static func isGrounded(_ expression: String, in command: String) -> Bool {
        let text = normalized(command)
        var allowed = Set(numbers(in: text))
        if text.contains("percent") || text.contains("%") { allowed.insert(100) }
        if text.contains("half") || text.contains("squared") { allowed.insert(2) }
        if text.contains("third") || text.contains("cubed") { allowed.insert(3) }
        if text.contains("quarter") { allowed.insert(4) }
        let used = numbers(in: expression)
        return !used.isEmpty && used.allSatisfy(allowed.contains)
    }

    /// Lowercased, thousands separators dropped ("1,000" → "1000"), punctuation and fillers removed.
    private static func normalized(_ command: String) -> String {
        var text = command.lowercased().replacingOccurrences(of: #"(?<=\d),(?=\d{3}\b)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<=\d)\s*%"#, with: " percent", options: .regularExpression)
        text = text.replacingOccurrences(of: "what's", with: "what")
        for (phrase, replacement) in phrases { text = text.replacingOccurrences(of: phrase, with: replacement) }
        let words = text.split(whereSeparator: \.isWhitespace).map { word in
            word.trimmingCharacters(in: CharacterSet(charactersIn: "?!,").union(.whitespaces))
                .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        }
        return words.filter { !$0.isEmpty && !fillers.contains($0) }.joined(separator: " ")
    }

    private static func percentOf(_ text: String) -> String? {
        guard let groups = match(#"^\#(number) percent of \#(number)$"#, text) else { return nil }
        return "\(groups[1]) * \(groups[0]) / 100"
    }

    private static func fractionOf(_ text: String) -> String? {
        for fraction in fractions {
            if let groups = match(#"^(?:a |one )?\#(fraction.word) of \#(number)$"#, text) {
                return "\(groups[0]) / \(fraction.divisor)"
            }
        }
        return nil
    }

    private static func power(_ text: String) -> String? {
        if let groups = match(#"^\#(number) squared$"#, text) { return "\(groups[0]) ^ 2" }
        if let groups = match(#"^\#(number) cubed$"#, text) { return "\(groups[0]) ^ 3" }
        return nil
    }

    /// "45 plus 17 minus 3" → "45 + 17 - 3"; any other word rejects.
    private static func operatorChain(_ text: String) -> String? {
        var tokens: [String] = []
        for word in text.split(separator: " ").map(String.init) {
            if let op = operatorWords[word] {
                tokens.append(op)
            } else if word.range(of: #"^\d+(?:\.\d+)?$"#, options: .regularExpression) != nil {
                tokens.append(word)
            } else if word.hasSuffix("squared"), let base = Double(word.dropLast(7)) {
                tokens.append("\(base.formatted(.number.grouping(.never))) ^ 2")
            } else {
                return nil
            }
        }
        let operators = Set(operatorWords.values)
        let isAlternating = tokens.count >= 3 && tokens.count % 2 == 1 && tokens.enumerated().allSatisfy { index, token in
            (index % 2 == 0) == !operators.contains(token)
        }
        return isAlternating ? tokens.joined(separator: " ") : nil
    }

    private static func numbers(in text: String) -> [Double] {
        text.matches(of: /\d+(?:\.\d+)?/).compactMap { Double($0.output) }
    }

    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        else { return nil }
        let source = text as NSString
        return (1..<result.numberOfRanges).map { source.substring(with: result.range(at: $0)) }
    }
}
