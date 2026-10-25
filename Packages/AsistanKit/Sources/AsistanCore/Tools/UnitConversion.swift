import Foundation

/// "10 mil kaç kilometre", "5 feet 10 inç kaç santim", "how many cups in 2 liters": read and computed
/// by rule, because the language model's arithmetic on units is unreliable.
public struct UnitConversion: Equatable, Sendable {
    public struct Quantity: Equatable, Sendable {
        public let value: Double
        public let unit: ConvertibleUnit
    }

    /// Several only for one length said in parts ("5 feet 10 inç").
    public let quantities: [Quantity]
    public let target: ConvertibleUnit

    public var result: Double {
        quantities.reduce(0) { total, quantity in
            total + Measurement(value: quantity.value, unit: quantity.unit.dimension).converted(to: target.dimension).value
        }
    }

    private static let turkishCues: Set<String> = ["kac", "kadar", "eder", "yapar", "esittir", "esit"]
    private static let turkishCueStems = ["cevir", "donustur"]
    private static let englishCues: Set<String> = ["in", "to", "into", "convert", "how", "equals", "equal", "is", "are", "makes"]
    /// Time arithmetic ("3 saat sonra saat kaç") rather than a conversion.
    private static let rejectedWords: Set<String> = ["sonra", "once", "later", "ago", "from"]
    private static let turkishNumberWords: [String: Double] = ["bir": 1, "on": 10, "yuz": 100, "yarim": 0.5]
    private static let englishNumberWords: [String: Double] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "twelve": 12, "twenty": 20, "fifty": 50, "hundred": 100, "half": 0.5,
    ]
    private static let suffixes: Set<String> = [
        "a", "e", "i", "u", "ya", "ye", "yi", "yu", "in", "un", "nin", "nun", "yin", "yun", "da", "de", "ta", "te",
        "dan", "den", "tan", "ten", "yla", "yle", "la", "le", "lik", "luk", "dir", "tir", "dur", "tur", "lar", "ler",
        "si", "su", "ina", "ine", "ini", "inda", "inde", "ndan", "nden",
    ]
    private static let formTable: [(words: [String], unit: ConvertibleUnit)] = ConvertibleUnit.allCases
        .flatMap { unit in unit.forms.map { (words: $0.split(separator: " ").map(String.init), unit: unit) } }
        .sorted { ($0.words.count, $0.words.joined().count) > ($1.words.count, $1.words.joined().count) }

    public static func parse(_ text: String, language: AssistantLanguage) -> UnitConversion? {
        let source = language == .turkish ? TurkishNumberParser.digitize(text) : text
        let tokens = tokenize(source)
        guard !tokens.contains(where: rejectedWords.contains), hasCue(tokens, language: language) else { return nil }
        var quantities: [Quantity] = []
        var bareUnits: [ConvertibleUnit] = []
        var index = 0
        while index < tokens.count {
            if let value = number(tokens[index], language: language), let (unit, length) = unit(at: index + 1, in: tokens) {
                quantities.append(Quantity(value: value, unit: unit))
                index += 1 + length
            } else if let (unit, length) = unit(at: index, in: tokens) {
                bareUnits.append(unit)
                index += length
            } else {
                index += 1
            }
        }
        guard let kind = quantities.first?.unit.kind, quantities.allSatisfy({ $0.unit.kind == kind }),
              quantities.count == 1 || kind != .temperature else { return nil }
        let targets = Set(bareUnits.filter { $0.kind == kind })
        guard targets.count == 1, let target = targets.first,
              quantities.count > 1 || quantities[0].unit != target else { return nil }
        return UnitConversion(quantities: quantities, target: target)
    }

    /// "10 mil 16,09 kilometre eder." / "10 miles is 16.09 kilometers."
    public func answer(language: AssistantLanguage) -> String {
        let said = quantities.map { $0.unit.spoken(Self.display($0.value, language), value: $0.value, language: language) }
            .joined(separator: " ")
        let converted = target.spoken(Self.display(result, language), value: result, language: language)
        let sentence = language == .turkish ? "\(said) \(converted) eder." : "\(said) is \(converted)."
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    static func display(_ value: Double, _ language: AssistantLanguage) -> String {
        let style = FloatingPointFormatStyle<Double>.number.locale(language.locale)
        if value != 0, abs(value) < 0.01 { return value.formatted(style.precision(.significantDigits(1...3))) }
        return value.formatted(style.precision(.fractionLength(0...2)))
    }

    private static func hasCue(_ tokens: [String], language: AssistantLanguage) -> Bool {
        tokens.contains { token in
            language == .english
                ? englishCues.contains(token)
                : turkishCues.contains(token) || turkishCueStems.contains(where: token.hasPrefix)
        }
    }

    private static func unit(at index: Int, in tokens: [String]) -> (ConvertibleUnit, Int)? {
        for form in formTable where index + form.words.count <= tokens.count {
            let said = tokens[index..<index + form.words.count]
            let leading = zip(said.dropLast(), form.words.dropLast()).allSatisfy { $0 == $1 }
            if leading, let last = said.last, let formLast = form.words.last, matches(last, formLast) {
                return (form.unit, form.words.count)
            }
        }
        return nil
    }

    /// The word itself, or the word with a Turkish case ending ("kilometreye", "bardağı").
    private static func matches(_ token: String, _ form: String) -> Bool {
        if token == form { return true }
        guard form.count >= 2, token.hasPrefix(form) else { return false }
        return suffixes.contains(String(token.dropFirst(form.count)))
    }

    private static func number(_ token: String, language: AssistantLanguage) -> Double? {
        if let word = (language == .english ? englishNumberWords : turkishNumberWords)[token] { return word }
        guard token.first?.isNumber == true else { return nil }
        let thousands = language == .english ? /^\d{1,3}(,\d{3})+$/ : /^\d{1,3}(\.\d{3})+$/
        if token.wholeMatch(of: thousands) != nil {
            return Double(token.filter(\.isNumber))
        }
        return Double(language == .english ? token.replacingOccurrences(of: ",", with: "") : token.replacingOccurrences(of: ",", with: "."))
    }

    /// Lowercase folded words and numbers; "2,5" and "1.5" stay whole, "10km" splits, "m²" becomes "m2".
    static func tokenize(_ text: String) -> [String] {
        let prepared = TurkishText.lowercased(text)
            .replacingOccurrences(of: "²", with: "2")
            .replacingOccurrences(of: "°f", with: " fahrenheit ")
            .replacingOccurrences(of: "°c", with: " celsius ")
            .replacingOccurrences(of: "°", with: " derece ")
        let characters = Array(prepared)
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(current) }
            current = ""
        }
        for (index, character) in characters.enumerated() {
            let next = index + 1 < characters.count ? characters[index + 1] : " "
            if character.isNumber {
                // "m2" and "km2" keep their digit; "kat3" does not.
                if current.last?.isLetter == true, !["m", "km"].contains(current) { flush() }
                current.append(character)
            } else if character.isLetter {
                if current.last?.isNumber == true, !current.contains(where: \.isLetter) { flush() }
                current.append(character)
            } else if character == "." || character == ",", current.last?.isNumber == true, next.isNumber {
                current.append(character)
            } else if !"'’‘`´".contains(character) {
                flush()
            }
        }
        flush()
        return tokens.map { token in token.first?.isNumber == true ? token : TurkishText.folded(token) }
    }
}
