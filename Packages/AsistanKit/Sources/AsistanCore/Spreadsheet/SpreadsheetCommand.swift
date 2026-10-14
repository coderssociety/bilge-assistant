import Foundation

/// A spoken spreadsheet edit, parsed without a language model so cell names and numbers are never
/// guessed: "D3'e B2 ile B1'i topla" → D3 = "=B2+B1". Formulas use Excel's English function names,
/// which it accepts whatever the user interface language.
public enum SpreadsheetCommand: Equatable, Sendable {
    case setFormula(target: CellReference, formula: String)
    case setValue(target: CellReference, value: SpreadsheetValue)
    case read(CellReference)
    case clear(CellReference)
    case copy(from: CellReference, to: CellReference)
    /// A question ("B1'den B9'a kadar toplam kaç"): computed and spoken, nothing is written.
    case evaluate(formula: String)
    case undo
    /// Leaves spreadsheet mode.
    case finish

    private enum Operation {
        case sum, subtract, multiply, divide, average, maximum, minimum, count, write, read, clear, copy
    }

    private static let finishPhrases: Set<String> = ["bitti", "tamam bitti", "tamamdir bitti", "is bitti", "excel bitti"]
    private static let operators: [String: String] = ["arti": "+", "eksi": "-", "carpi": "*", "bolu": "/"]
    private static let writeWords: Set<String> = ["yaz", "yazar", "yazsana", "yazin", "koy", "gir"]
    private static let readWords: Set<String> = ["oku", "okur", "okusana", "kac", "degeri", "degerini"]
    private static let clearWords: Set<String> = ["sil", "silsene", "temizle", "bosalt"]
    private static let questionWords: Set<String> = ["kac", "ne", "nedir", "neymis"]

    public static func parse(_ text: String) -> SpreadsheetCommand? {
        let folded = TurkishText.folded(text)
        let foldedWords = folded.split(separator: " ").map(String.init)
        if finishPhrases.contains(folded)
            || (foldedWords.contains("excel") && foldedWords.contains { ["cik", "kapat", "bitir"].contains($0) || $0.hasPrefix("modundan") }) {
            return .finish
        }
        if folded.contains("geri al") || folded.contains("geri getir") { return .undo }

        let tokens = SpreadsheetTokenizer.tokens(text)
        guard tokens.contains(where: { $0.cell != nil || isColumn($0) }) else { return nil }
        let words = tokens.compactMap(\.word)
        guard let operation = operation(words) else { return nil }
        return build(operation, tokens: tokens, words: words)
    }

    /// True when the command talks about cells at all ("D2'ye KDV'li fiyatı hesapla"), even if no rule
    /// understood it: in spreadsheet mode such requests go to the language model for a formula.
    public static func mentionsCells(_ text: String) -> Bool {
        let tokens = SpreadsheetTokenizer.tokens(TurkishNumberParser.digitize(text))
        if tokens.contains(where: { $0.cell != nil || isColumn($0) }) { return true }
        return tokens.compactMap(\.word).contains { word in ["hucre", "sutun", "satir", "formul"].contains(where: word.hasPrefix) }
    }

    // MARK: - Recognizing the operation

    private static func operation(_ words: [String]) -> Operation? {
        func has(_ prefix: String) -> Bool { words.contains { $0.hasPrefix(prefix) } }
        func after(_ first: String, _ prefixes: [String]) -> Bool {
            zip(words, words.dropFirst()).contains { $0 == first && prefixes.contains(where: $1.hasPrefix) }
        }
        if has("kopyala") { return .copy }
        if words.contains(where: clearWords.contains) { return .clear }
        if has("ortalama") { return .average }
        if after("en", ["buyu", "yuksek", "fazla"]) || has("maksimum") { return .maximum }
        if after("en", ["kucu", "dusuk", "az"]) || has("minimum") { return .minimum }
        if has("topla") || has("toplam") { return .sum }
        if has("cikar") { return .subtract }
        if words.contains(where: { $0.hasPrefix("carp") && $0 != "carpi" }) { return .multiply }
        if words.contains(where: { $0.hasPrefix("bol") && $0 != "bolu" }) { return .divide }
        if words.contains("say") || has("sayisi") { return .count }
        if words.contains(where: writeWords.contains) || words.contains("esittir") || words.contains("esit") { return .write }
        if words.contains(where: readWords.contains) || (words.contains("ne") && words.contains("var")) { return .read }
        return nil
    }

    // MARK: - Building the command

    private static func build(_ operation: Operation, tokens: [SpreadsheetToken], words: [String]) -> SpreadsheetCommand? {
        switch operation {
        case .copy:
            guard let source = tokens.first(where: { $0.cell != nil && $0.grammaticalCase != .dative })?.cell,
                  let destination = tokens.first(where: { $0.cell != nil && $0.grammaticalCase == .dative })?.cell
            else { return nil }
            return .copy(from: source, to: destination)
        case .clear:
            let cells = tokens.compactMap(\.cell)
            return cells.count == 1 ? .clear(cells[0]) : nil
        case .read:
            let cells = tokens.compactMap(\.cell)
            return cells.count == 1 ? .read(cells[0]) : nil
        default:
            return compute(operation, tokens: tokens, words: words)
        }
    }

    private static func compute(_ operation: Operation, tokens: [SpreadsheetToken], words: [String]) -> SpreadsheetCommand? {
        var remaining = tokens
        let range = takeRange(&remaining)
        let target = takeTarget(&remaining, operation: operation)
        let operands = remaining.filter { $0.cell != nil || isNumber($0) }

        let expression: String
        switch operation {
        case .average, .maximum, .minimum, .count:
            guard let arguments = range ?? list(operands) else { return nil }
            expression = "\(function(operation))(\(arguments))"
        case .sum:
            if let range {
                expression = "SUM(\(range))"
            } else {
                guard operands.count >= 2 else { return nil }
                expression = operands.map(operand).joined(separator: "+")
            }
        case .subtract:
            guard operands.count >= 2 else { return nil }
            let minuend = operands.first { $0.grammaticalCase == .ablative } ?? operands[0]
            let rest = operands.filter { $0 != minuend }
            expression = ([minuend] + rest).map(operand).joined(separator: "-")
        case .multiply:
            guard operands.count >= 2 else { return nil }
            expression = operands.map(operand).joined(separator: "*")
        case .divide:
            guard operands.count == 2 else { return nil }
            let divisor = operands.first { $0.grammaticalCase == .dative } ?? operands[1]
            let dividend = operands.first { $0 != divisor } ?? operands[0]
            expression = "\(operand(dividend))/\(operand(divisor))"
        case .write:
            guard let target else { return nil }
            return write(into: target, tokens: remaining)
        case .read, .clear, .copy:
            return nil
        }
        guard let target else { return .evaluate(formula: expression) }
        return .setFormula(target: target, formula: "=" + expression)
    }

    /// "C5'e 1250 yaz" → a number; "D3'e B2 artı B1 yaz" → a formula; "A1'e Kira Gideri yaz" → text.
    private static func write(into target: CellReference, tokens: [SpreadsheetToken]) -> SpreadsheetCommand? {
        let content = tokens.filter { token in
            guard let word = token.word else { return true }
            return !writeWords.contains(word) && word != "esittir" && word != "esit" && word != "olsun"
        }
        guard !content.isEmpty else { return nil }
        if content.contains(where: { $0.word.flatMap { operators[$0] } != nil }) {
            var parts: [String] = []
            for token in content {
                if let word = token.word {
                    guard let symbol = operators[word] else { return nil }
                    parts.append(symbol)
                } else {
                    parts.append(operand(token))
                }
            }
            return .setFormula(target: target, formula: "=" + parts.joined())
        }
        if content.count == 1, case let .number(value) = content[0].kind {
            return .setValue(target: target, value: .number(value))
        }
        guard content.allSatisfy({ $0.word != nil || isNumber($0) }) else { return nil }
        return .setValue(target: target, value: .text(content.map(\.original).joined(separator: " ")))
    }

    /// "B1'den B9'a kadar", "C2 ile C11 arası", "C sütunu" → "B1:B9"; the cells are taken out of `tokens`.
    private static func takeRange(_ tokens: inout [SpreadsheetToken]) -> String? {
        if let index = tokens.firstIndex(where: isColumn), case let .column(letter) = tokens[index].kind {
            tokens.remove(at: index)
            return "\(letter):\(letter)"
        }
        for start in tokens.indices where tokens[start].cell != nil {
            let next = start + 1
            guard next < tokens.count, let first = tokens[start].cell else { continue }
            if tokens[start].grammaticalCase == .ablative, let end = tokens[next].cell, tokens[next].grammaticalCase == .dative,
               next + 1 < tokens.count, tokens[next + 1].word == "kadar" {
                tokens.removeSubrange(start...(next + 1))
                return "\(first.address):\(end.address)"
            }
            if tokens[next].word == "ile", next + 2 < tokens.count, let end = tokens[next + 1].cell,
               tokens[next + 2].word?.hasPrefix("arasi") == true {
                tokens.removeSubrange(start...(next + 2))
                return "\(first.address):\(end.address)"
            }
        }
        return nil
    }

    /// Where the result goes: the cell before "eşittir", the cell just before "yaz", or else the first
    /// cell in the dative ("D3'e"). A divisor ("B1'e böl") is in the dative too, so it is skipped.
    private static func takeTarget(_ tokens: inout [SpreadsheetToken], operation: Operation) -> CellReference? {
        if let equals = tokens.firstIndex(where: { $0.word == "esittir" || $0.word == "esit" }), equals > 0,
           let cell = tokens[equals - 1].cell {
            tokens.remove(at: equals - 1)
            return cell
        }
        let datives = tokens.indices.filter { tokens[$0].cell != nil && tokens[$0].grammaticalCase == .dative }
        var candidates = datives
        if operation == .divide, datives.count >= 1 {
            let divideIndex = tokens.firstIndex { $0.word?.hasPrefix("bol") == true && $0.word != "bolu" } ?? tokens.endIndex
            if let divisor = datives.last(where: { $0 < divideIndex }), datives.count >= 2 || divisor == divideIndex - 1 {
                candidates.removeAll { $0 == divisor }
            }
        }
        if let writeIndex = tokens.firstIndex(where: { $0.word.map(writeWords.contains) ?? false }),
           let beforeWrite = candidates.last(where: { $0 < writeIndex }) {
            return tokens.remove(at: beforeWrite).cell
        }
        guard let first = candidates.first else { return nil }
        return tokens.remove(at: first).cell
    }

    private static func function(_ operation: Operation) -> String {
        switch operation {
        case .average: "AVERAGE"
        case .maximum: "MAX"
        case .minimum: "MIN"
        case .count: "COUNT"
        default: "SUM"
        }
    }

    private static func list(_ operands: [SpreadsheetToken]) -> String? {
        operands.count >= 2 ? operands.map(operand).joined(separator: ",") : nil
    }

    private static func operand(_ token: SpreadsheetToken) -> String {
        switch token.kind {
        case let .cell(cell): cell.address
        case let .number(value): value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case let .column(letter): "\(letter):\(letter)"
        case let .word(word): word
        }
    }

    private static func isNumber(_ token: SpreadsheetToken) -> Bool {
        if case .number = token.kind { true } else { false }
    }

    private static func isColumn(_ token: SpreadsheetToken) -> Bool {
        if case .column = token.kind { true } else { false }
    }
}
