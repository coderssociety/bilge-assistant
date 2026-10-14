import Foundation

/// A spoken spreadsheet command split into cells, numbers and words. Turkish case endings carry the
/// grammar: "D3'e" is where something goes, "B1'den" where a range or a subtraction starts.
struct SpreadsheetToken: Equatable {
    enum Case: Equatable {
        case none, dative, ablative, accusative, locative, genitive
    }

    enum Kind: Equatable {
        case cell(CellReference)
        /// A whole column, "C sütunu" → "C:C".
        case column(String)
        case number(Double)
        case word(String)
    }

    let kind: Kind
    var grammaticalCase: Case
    /// As spoken, for text written into a cell.
    let original: String

    var word: String? {
        if case let .word(word) = kind { word } else { nil }
    }

    var cell: CellReference? {
        if case let .cell(cell) = kind { cell } else { nil }
    }
}

extension SpreadsheetToken.Kind {
    var isNumber: Bool {
        if case .number = self { true } else { false }
    }
}

enum SpreadsheetTokenizer {
    /// Spoken letter names, as dictation writes them when a column is said on its own ("de üç").
    /// "ve" is left out: it is "and" far more often than column V; "x" too, which may be "times".
    private static let letterNames: [String: String] = [
        "a": "A", "be": "B", "b": "B", "ce": "C", "c": "C", "de": "D", "d": "D", "e": "E", "fe": "F", "f": "F",
        "ge": "G", "g": "G", "he": "H", "ha": "H", "h": "H", "i": "I", "je": "J", "j": "J", "ke": "K", "ka": "K",
        "k": "K", "le": "L", "l": "L", "me": "M", "m": "M", "ne": "N", "n": "N", "o": "O", "pe": "P", "p": "P",
        "ku": "Q", "q": "Q", "re": "R", "r": "R", "se": "S", "s": "S", "te": "T", "t": "T", "u": "U",
        "w": "W", "iks": "X", "ye": "Y", "y": "Y", "ze": "Z", "z": "Z",
    ]
    private static let symbolWords: [(String, String)] = [
        ("+", " artı "), ("×", " çarpı "), ("*", " çarpı "), ("=", " eşittir "), ("/", " bölü "), (" - ", " eksi "),
    ]
    private static let apostrophes: Set<Character> = ["'", "’", "‘", "`", "´"]

    static func tokens(_ text: String) -> [SpreadsheetToken] {
        var spaced = text
        for (symbol, word) in symbolWords { spaced = spaced.replacingOccurrences(of: symbol, with: word) }
        let pieces = spaced.split(whereSeparator: \.isWhitespace).map { piece in
            piece.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?()\"“”"))
        }.filter { !$0.isEmpty }
        var tokens: [SpreadsheetToken] = []
        var index = 0
        while index < pieces.count {
            let piece = pieces[index]
            let (base, suffix) = split(piece)
            if let letter = letterNames[base], suffix.isEmpty, index + 1 < pieces.count {
                let (spokenBase, nextSuffix) = split(pieces[index + 1])
                // Number parsing leaves "bir" alone (it is usually "a"), but after a column letter it is 1.
                let nextBase = spokenBase == "bir" ? "1" : spokenBase
                if Int(nextBase) != nil, let cell = CellReference(letter + nextBase) {
                    tokens.append(SpreadsheetToken(kind: .cell(cell), grammaticalCase: grammaticalCase(nextSuffix),
                                                   original: piece + " " + pieces[index + 1]))
                    index += 2
                    continue
                }
                if nextBase.hasPrefix("sutun") {
                    tokens.append(SpreadsheetToken(kind: .column(letter), grammaticalCase: .none, original: piece))
                    index += 2
                    continue
                }
            }
            tokens.append(token(piece, base: base, suffix: suffix))
            index += 1
        }
        return attachCellWords(tokens)
    }

    /// "D3'e" → ("d3", "e"); "d3e" → ("d3", "e"); "topla" → ("topla", "").
    private static func split(_ piece: String) -> (String, String) {
        let lowered = TurkishText.lowercased(piece)
        if let mark = lowered.firstIndex(where: apostrophes.contains) {
            return (fold(String(lowered[..<mark])), fold(String(lowered[lowered.index(after: mark)...])))
        }
        let folded = fold(lowered)
        let letters = folded.prefix { $0.isASCII && $0.isLetter }
        let digits = folded.dropFirst(letters.count).prefix { $0.isNumber }
        let rest = folded.dropFirst(letters.count + digits.count)
        if (0...3).contains(letters.count), !digits.isEmpty, rest.allSatisfy(\.isLetter), !(letters.isEmpty && !rest.isEmpty) {
            return (String(letters + digits), String(rest))
        }
        return (folded, "")
    }

    private static func token(_ piece: String, base: String, suffix: String) -> SpreadsheetToken {
        let grammatical = grammaticalCase(suffix)
        if let cell = CellReference(base), base.first?.isLetter == true {
            return SpreadsheetToken(kind: .cell(cell), grammaticalCase: grammatical, original: piece)
        }
        if let number = Double(base.replacingOccurrences(of: ",", with: ".")), base.first?.isNumber == true {
            return SpreadsheetToken(kind: .number(number), grammaticalCase: grammatical, original: piece)
        }
        return SpreadsheetToken(kind: .word(base + suffix), grammaticalCase: .none, original: piece)
    }

    /// "D3 hücresine" gives D3 the case of "hücresine"; "d3 e", where dictation split off the
    /// ending, gives it the case of "e".
    private static func attachCellWords(_ tokens: [SpreadsheetToken]) -> [SpreadsheetToken] {
        var result: [SpreadsheetToken] = []
        for token in tokens {
            if var previous = result.last, previous.cell != nil || previous.kind.isNumber, previous.grammaticalCase == .none,
               let word = token.word {
                let ending = word.hasPrefix("hucresi") ? String(word.dropFirst("hucresi".count)) : word
                let attached = grammaticalCase(ending)
                if word.hasPrefix("hucre") || attached != .none {
                    previous.grammaticalCase = attached
                    result[result.count - 1] = previous
                    continue
                }
            }
            result.append(token)
        }
        return result
    }

    private static func grammaticalCase(_ suffix: String) -> SpreadsheetToken.Case {
        switch suffix {
        case "e", "a", "ye", "ya", "ne", "na": .dative
        case "den", "dan", "ten", "tan", "nden", "ndan": .ablative
        case "i", "u", "yi", "yu", "ni", "nu": .accusative
        case "de", "da", "te", "ta", "nde", "nda": .locative
        case "in", "un", "nin", "nun": .genitive
        default: .none
        }
    }

    private static let diacriticFolds: [Character: Character] = [
        "ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "â": "a", "î": "i", "û": "u",
    ]

    /// Lowercase without Turkish letters, keeping digits and the decimal comma ("12,5") intact.
    private static func fold(_ text: String) -> String {
        String(TurkishText.lowercased(text).map { diacriticFolds[$0] ?? $0 })
    }
}
