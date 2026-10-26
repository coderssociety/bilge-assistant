import Foundation

/// Recursive-descent evaluator for + - * / % ^ and parentheses. Deliberately not NSExpression,
/// which can call arbitrary functions when fed model-generated text.
public enum ArithmeticEvaluator {
    public enum EvaluationError: Error, Equatable {
        case empty
        case unexpectedCharacter(Character)
        case unexpectedEnd
        case unbalancedParentheses
        case divisionByZero
        case notFinite
    }

    private static let maxFractionDigits = 4

    public static func evaluate(_ expression: String) throws -> Double {
        var parser = Parser(tokens: try tokenize(expression))
        guard !parser.tokens.isEmpty else { throw EvaluationError.empty }
        let value = try parser.parseExpression()
        guard parser.isAtEnd else { throw EvaluationError.unbalancedParentheses }
        guard value.isFinite else { throw EvaluationError.notFinite }
        return value
    }

    /// Decimal comma in Turkish ("22,5"), point in English ("22.5").
    public static func display(_ value: Double, language: AssistantLanguage = .turkish) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)).grouping(.never).locale(language.locale))
    }

    private enum Token: Equatable {
        case number(Double)
        case op(Character)
        case open, close
    }

    private static func tokenize(_ text: String) throws -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isWhitespace {
                index = text.index(after: index)
            } else if character.isNumber {
                var end = index
                while end < text.endIndex, text[end].isNumber || text[end] == "." || text[end] == "," {
                    end = text.index(after: end)
                }
                let literal = text[index..<end].replacingOccurrences(of: ",", with: ".")
                guard let value = Double(literal) else { throw EvaluationError.unexpectedCharacter(character) }
                tokens.append(.number(value))
                index = end
            } else if "+-*/%^×÷".contains(character) {
                tokens.append(.op(character == "×" ? "*" : character == "÷" ? "/" : character))
                index = text.index(after: index)
            } else if character == "(" {
                tokens.append(.open)
                index = text.index(after: index)
            } else if character == ")" {
                tokens.append(.close)
                index = text.index(after: index)
            } else {
                throw EvaluationError.unexpectedCharacter(character)
            }
        }
        return tokens
    }

    private struct Parser {
        let tokens: [Token]
        var position = 0

        var isAtEnd: Bool { position == tokens.count }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while case let .op(op)? = peek(), op == "+" || op == "-" {
                position += 1
                let rhs = try parseTerm()
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() throws -> Double {
            var value = try parsePower()
            while case let .op(op)? = peek(), op == "*" || op == "/" || op == "%" {
                position += 1
                let rhs = try parsePower()
                if op != "*", rhs == 0 { throw EvaluationError.divisionByZero }
                value = op == "*" ? value * rhs : op == "/" ? value / rhs : value.truncatingRemainder(dividingBy: rhs)
            }
            return value
        }

        mutating func parsePower() throws -> Double {
            let base = try parseUnary()
            guard case .op("^")? = peek() else { return base }
            position += 1
            let result = pow(base, try parsePower())
            guard result.isFinite else { throw EvaluationError.notFinite }
            return result
        }

        mutating func parseUnary() throws -> Double {
            if case let .op(op)? = peek(), op == "-" || op == "+" {
                position += 1
                let value = try parseUnary()
                return op == "-" ? -value : value
            }
            return try parsePrimary()
        }

        mutating func parsePrimary() throws -> Double {
            guard let token = next() else { throw EvaluationError.unexpectedEnd }
            switch token {
            case let .number(value):
                return value
            case .open:
                let value = try parseExpression()
                guard next() == .close else { throw EvaluationError.unbalancedParentheses }
                return value
            case .close:
                throw EvaluationError.unbalancedParentheses
            case let .op(op):
                throw EvaluationError.unexpectedCharacter(op)
            }
        }

        private func peek() -> Token? { position < tokens.count ? tokens[position] : nil }

        private mutating func next() -> Token? {
            defer { position += 1 }
            return peek()
        }
    }
}
