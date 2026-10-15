import Foundation

/// English counterpart of `SpreadsheetCommand`'s Turkish rules. Turkish marks roles with case endings
/// ("D3'e" target, "B1'den" start); English uses word order and prepositions: "put the sum of B1 and B2
/// into D3", "set D3 to B2 plus B1", "sum of B1 to B9", "subtract B2 from B1", "copy D3 to E3".
enum EnglishSpreadsheetCommand {
    private enum Operation {
        case sum, subtract, multiply, divide, average, maximum, minimum, count, write, read, clear, copy
    }

    private enum Token: Equatable {
        case cell(CellReference)
        case column(String)
        case number(Double)
        case word(String, original: String)

        var cell: CellReference? { if case let .cell(cell) = self { cell } else { nil } }
        var word: String? { if case let .word(word, _) = self { word } else { nil } }
        var isColumn: Bool { if case .column = self { true } else { false } }
        var isOperand: Bool {
            switch self {
            case .cell, .number: true
            case .column, .word: false
            }
        }
    }

    private static let finishPhrases: Set<String> = ["done", "im done", "all done", "finish", "finished", "thats it"]
    private static let operators: [String: String] = ["plus": "+", "minus": "-", "times": "*", "over": "/", "+": "+", "-": "-", "*": "*", "/": "/"]
    private static let writeWords: Set<String> = ["write", "put", "type", "enter", "set", "make", "equals", "equal", "is"]
    private static let readWords: Set<String> = ["read", "whats", "what", "value", "say", "says"]
    private static let clearWords: Set<String> = ["clear", "delete", "erase", "empty", "remove"]
    private static let rangeWords: Set<String> = ["to", "through", "thru", "until"]
    private static let targetWords: Set<String> = ["into", "in", "to"]
    private static let fillers: Set<String> = [
        "the", "of", "and", "a", "an", "cell", "cells", "please", "result", "answer", "number", "value", "by", "from", "with",
    ]

    static func parse(_ text: String) -> SpreadsheetCommand? {
        let folded = TurkishText.folded(text)
        let foldedWords = folded.split(separator: " ").map(String.init)
        if finishPhrases.contains(folded) || (foldedWords.contains("excel") && foldedWords.contains { ["exit", "leave", "quit", "close", "stop"].contains($0) }) {
            return .finish
        }
        if foldedWords.first == "undo" { return .undo }
        var tokens = tokenize(text)
        guard tokens.contains(where: { $0.cell != nil || $0.isColumn }) else { return nil }
        let words = tokens.compactMap(\.word)
        guard let operation = operation(words) else { return nil }
        switch operation {
        case .copy:
            guard let to = tokens.firstIndex(where: { $0.word == "to" || $0.word == "into" }),
                  let source = tokens[..<to].compactMap(\.cell).first, let destination = tokens[to...].compactMap(\.cell).first
            else { return nil }
            return .copy(from: source, to: destination)
        case .clear, .read:
            let cells = tokens.compactMap(\.cell)
            guard cells.count == 1 else { return nil }
            return operation == .clear ? .clear(cells[0]) : .read(cells[0])
        default:
            let range = takeRange(&tokens)
            let target = takeTarget(&tokens)
            return compute(operation, range: range, target: target, tokens: tokens)
        }
    }

    static func mentionsCells(_ text: String) -> Bool {
        let tokens = tokenize(text)
        if tokens.contains(where: { $0.cell != nil || $0.isColumn }) { return true }
        return tokens.compactMap(\.word).contains { ["cell", "column", "row", "formula"].contains($0) }
    }

    private static func operation(_ words: [String]) -> Operation? {
        let has = { (word: String) in words.contains(word) }
        if has("copy") { return .copy }
        if words.contains(where: clearWords.contains) { return .clear }
        if has("average") || has("mean") { return .average }
        if has("max") || has("maximum") || has("largest") || has("highest") || has("biggest") { return .maximum }
        if has("min") || has("minimum") || has("smallest") || has("lowest") { return .minimum }
        if has("count") || (has("how") && has("many")) { return .count }
        if words.contains(where: operators.keys.contains) && (words.contains(where: writeWords.contains) || has("equals")) { return .write }
        let asks = words.first == "what" || words.first == "whats"
        let computes = ["sum", "total", "add"].contains(where: has)
        if asks, !computes, !words.contains(where: operators.keys.contains) { return .read }
        if has("sum") || has("total") || has("add") { return .sum }
        if has("subtract") { return .subtract }
        if has("multiply") { return .multiply }
        if has("divide") { return .divide }
        if words.contains(where: writeWords.contains) { return .write }
        if words.contains(where: readWords.contains) { return .read }
        return nil
    }

    private static func compute(_ operation: Operation, range: String?, target: CellReference?, tokens: [Token]) -> SpreadsheetCommand? {
        let operands = tokens.filter(\.isOperand)
        let expression: String
        switch operation {
        case .average, .maximum, .minimum, .count:
            guard let arguments = range ?? (operands.count >= 2 ? operands.map(operand).joined(separator: ",") : nil) else { return nil }
            expression = "\(function(operation))(\(arguments))"
        case .sum:
            if let range {
                expression = "SUM(\(range))"
            } else {
                guard operands.count >= 2 else { return nil }
                expression = operands.map(operand).joined(separator: "+")
            }
        case .subtract:
            // "Subtract B2 from B1": what follows "from" is the minuend.
            guard operands.count == 2 else { return nil }
            let fromIndex = tokens.firstIndex { $0.word == "from" }
            let minuend = fromIndex.flatMap { index in tokens[index...].first(where: \.isOperand) } ?? operands[0]
            let subtrahend = operands.first { $0 != minuend } ?? operands[1]
            expression = "\(operand(minuend))-\(operand(subtrahend))"
        case .multiply:
            guard operands.count >= 2 else { return nil }
            expression = operands.map(operand).joined(separator: "*")
        case .divide:
            guard operands.count == 2 else { return nil }
            expression = "\(operand(operands[0]))/\(operand(operands[1]))"
        case .write:
            guard let target else { return nil }
            return write(into: target, tokens: tokens)
        case .read, .clear, .copy:
            return nil
        }
        guard let target else { return .evaluate(formula: expression) }
        return .setFormula(target: target, formula: "=" + expression)
    }

    /// "Write 1250 in C5" → a number; "set D3 to B2 plus B1" → a formula; "put Rent in A1" → text.
    private static func write(into target: CellReference, tokens: [Token]) -> SpreadsheetCommand? {
        let content = tokens.filter { token in
            guard let word = token.word else { return true }
            return !writeWords.contains(word) && !fillers.contains(word) && !targetWords.contains(word)
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
        if content.count == 1, case let .number(value) = content[0] { return .setValue(target: target, value: .number(value)) }
        let words = content.compactMap { token -> String? in
            if case let .word(_, original) = token { return original }
            if case let .number(value) = token { return operand(.number(value)) }
            return nil
        }
        guard words.count == content.count else { return nil }
        return .setValue(target: target, value: .text(words.joined(separator: " ")))
    }

    /// "B1 to B9", "from B1 through B9", "column B" → "B1:B9" / "B:B"; taken out of `tokens`.
    private static func takeRange(_ tokens: inout [Token]) -> String? {
        if let index = tokens.firstIndex(where: \.isColumn), case let .column(letter) = tokens[index] {
            tokens.remove(at: index)
            return "\(letter):\(letter)"
        }
        for start in tokens.indices {
            guard let first = tokens[start].cell, start + 2 < tokens.count, let word = tokens[start + 1].word,
                  rangeWords.contains(word), let end = tokens[start + 2].cell else { continue }
            // "copy B1 to B2" never gets here; "set D3 to B2" has no cell before "to" that starts a range of the same kind.
            if word == "to", start > 0, ["set", "make"].contains(tokens[start - 1].word ?? "") { continue }
            tokens.removeSubrange(start...(start + 2))
            return "\(first.address):\(end.address)"
        }
        return nil
    }

    /// The cell after "set"/"make" or before "equals"/"=", else the cell after a final "into"/"in"/"to".
    private static func takeTarget(_ tokens: inout [Token]) -> CellReference? {
        if let verb = tokens.firstIndex(where: { ["set", "make"].contains($0.word ?? "") }), verb + 1 < tokens.count,
           let cell = tokens[verb + 1].cell {
            tokens.remove(at: verb + 1)
            return cell
        }
        if let equals = tokens.firstIndex(where: { ["equals", "equal", "is", "="].contains($0.word ?? "") }), equals > 0,
           let cell = tokens[equals - 1].cell {
            tokens.remove(at: equals - 1)
            return cell
        }
        guard let index = tokens.indices.last(where: { index in
            index > 0 && tokens[index].cell != nil && targetWords.contains(tokens[index - 1].word ?? "")
        }) else { return nil }
        return tokens.remove(at: index).cell
    }

    private static func tokenize(_ text: String) -> [Token] {
        let pieces = text.replacingOccurrences(of: #"(?<=\d),(?=\d{3}\b)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "=", with: " = ")
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",.?!:;\"'“”")) }
            .filter { !$0.isEmpty }
        var tokens: [Token] = []
        var index = 0
        while index < pieces.count {
            let piece = pieces[index]
            let folded = TurkishText.folded(piece)
            if folded == "column", index + 1 < pieces.count, pieces[index + 1].count <= 2,
               pieces[index + 1].allSatisfy({ $0.isASCII && $0.isLetter }) {
                tokens.append(.column(pieces[index + 1].uppercased()))
                index += 2
                continue
            }
            // A recognizer may write "B 1" for B1.
            if piece.count == 1, piece.first?.isLetter == true, index + 1 < pieces.count, Int(pieces[index + 1]) != nil,
               let cell = CellReference(piece + pieces[index + 1]) {
                tokens.append(.cell(cell))
                index += 2
                continue
            }
            if let cell = CellReference(piece), piece.first?.isLetter == true {
                tokens.append(.cell(cell))
            } else if let value = Double(piece) {
                tokens.append(.number(value))
            } else if piece == "=" {
                tokens.append(.word("=", original: "="))
            } else {
                tokens.append(.word(folded, original: piece))
            }
            index += 1
        }
        return tokens
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

    private static func operand(_ token: Token) -> String {
        switch token {
        case let .cell(cell): cell.address
        case let .number(value): value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case let .column(letter): "\(letter):\(letter)"
        case let .word(word, _): word
        }
    }
}
