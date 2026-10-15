import Foundation

/// Turns common spoken Turkish arithmetic (already digitized by TurkishNumberParser) into an
/// expression for ArithmeticEvaluator, and checks that a model-written expression only uses numbers
/// the user actually said. The model has invented whole calculations for a bare "Evet".
public enum TurkishArithmeticParser {
    private static let number = #"(\d+(?:[.,]\d+)?)"#
    private static let suffix = #"(?:'\p{L}+)?"#
    private static let fillers: Set<String> = [
        "kac", "eder", "kactir", "ne", "kadar", "hesapla", "nedir", "olur", "yapar", "acaba", "bana", "lutfen", "soyle",
    ]
    private static let operatorWords: [String: String] = [
        "arti": "+", "+": "+", "eksi": "-", "-": "-", "carpi": "*", "kere": "*", "x": "*", "×": "*", "*": "*",
        "bolu": "/", "÷": "/", "/": "/", "ussu": "^", "^": "^",
    ]
    private static let fractions: [(word: String, divisor: Int)] = [("yarisi", 2), ("ceyregi", 4), ("ucte biri", 3)]

    public static func expression(from command: String) -> String? {
        let text = TurkishText.lowercased(command).trimmingCharacters(in: .whitespacesAndNewlines)
        return percentOf(text) ?? fractionOf(text) ?? powerOf(text) ?? operatorChain(text)
    }

    public static func isGrounded(_ expression: String, in command: String) -> Bool {
        let said = Set(numbers(in: command))
        let folded = TurkishText.folded(command)
        var allowed = said
        if command.contains("%") || folded.contains("yuzde") { allowed.insert(100) }
        if folded.contains("yari") { allowed.insert(2) }
        if folded.contains("ceyrek") { allowed.insert(4) }
        if folded.contains("ucte") { allowed.insert(3) }
        let used = numbers(in: expression)
        return !used.isEmpty && used.allSatisfy(allowed.contains)
    }

    private static func percentOf(_ text: String) -> String? {
        guard let groups = match(#"^\#(number)\#(suffix)\s+(?:%|yüzde\s*)\#(number)\#(suffix)(.*)$"#, text),
              onlyFillers(groups[2]) else { return nil }
        return "\(groups[0]) * \(groups[1]) / 100"
    }

    private static func fractionOf(_ text: String) -> String? {
        for fraction in fractions {
            let pattern = #"^\#(number)\#(suffix)\s+(.+)$"#
            guard let groups = match(pattern, text) else { return nil }
            let rest = TurkishText.folded(groups[1])
            guard rest.hasPrefix(fraction.word), onlyFillers(String(rest.dropFirst(fraction.word.count))) else { continue }
            return "\(groups[0]) / \(fraction.divisor)"
        }
        return nil
    }

    private static func powerOf(_ text: String) -> String? {
        guard let groups = match(#"^\#(number)\#(suffix)\s+\#(number)\.?\s*kuvveti(.*)$"#, text),
              onlyFillers(groups[2]) else { return nil }
        return "\(groups[0]) ^ \(groups[1])"
    }

    /// "45 artı 17 eksi 3" → "45 + 17 - 3"; everything except numbers, operators and filler words rejects.
    private static func operatorChain(_ text: String) -> String? {
        var tokens: [String] = []
        for raw in text.split(separator: " ").map(String.init) {
            let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: "?.!,"))
            let key = TurkishText.folded(word)
            if let op = operatorWords[key] ?? operatorWords[word] {
                tokens.append(op)
            } else if word.range(of: #"^\d+(?:[.,]\d+)?$"#, options: .regularExpression) != nil {
                tokens.append(word)
            } else if fillers.contains(key) || key.isEmpty {
                continue
            } else {
                return nil
            }
        }
        let isAlternating = tokens.count >= 3 && tokens.count % 2 == 1 && tokens.enumerated().allSatisfy { index, token in
            (index % 2 == 0) == (operatorWords.values.contains(token) == false)
        }
        return isAlternating ? tokens.joined(separator: " ") : nil
    }

    private static func onlyFillers(_ rest: String) -> Bool {
        TurkishText.folded(rest).split(separator: " ").allSatisfy { fillers.contains(String($0)) }
    }

    private static func numbers(in text: String) -> [Double] {
        let regex = try! NSRegularExpression(pattern: number)
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap {
            Double(source.substring(with: $0.range(at: 1)).replacingOccurrences(of: ",", with: "."))
        }
    }

    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        else { return nil }
        let source = text as NSString
        return (1..<result.numberOfRanges).map { index in
            let range = result.range(at: index)
            return range.location == NSNotFound ? "" : source.substring(with: range)
        }
    }
}
