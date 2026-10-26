import CryptoKit
import Foundation

/// One of the user's own commands from Settings → Commands: a name to say and the program it runs, exactly as typed
/// there and without a shell. Shortcuts cover what an app can do; these cover what a terminal command can.
public struct CustomCommand: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// The program, then its arguments.
    public var arguments: [String]

    public init(id: UUID = UUID(), name: String, arguments: [String]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    /// Changes whenever the command does, so a command edited after the user said yes is asked about again.
    public var fingerprint: String {
        let data = (try? JSONEncoder().encode([name] + arguments)) ?? Data(name.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public var line: String { CommandLineText.join(arguments) }
}

public enum CustomCommandRequest {
    private static let commandWords = ["komut", "command"]
    private static let runStems = ["calistir", "baslat"]
    private static let leadingFillers: Set<String> = ["bilge", "lutfen", "benim", "su", "bu"]
    private static let myCommands: Set<String> = ["komutlarim", "komutlarimi", "komutlarimiz", "komutlarimin"]
    private static let listCues: Set<String> = ["neler", "ne", "listele", "hangi", "hangileri", "say", "goster", "oku", "var"]
    private static let englishListCues: Set<String> = ["list", "what", "which", "show"]
    // Regex values are not Sendable, so the pattern is built where used rather than stored.
    private static var englishRun: Regex<(Substring, Substring)> { /\b(?:run|start|execute)\s+(?:the\s+|my\s+)?(.+?)\s+command\b/.ignoresCase() }

    /// The name in "yedekleme komutunu çalıştır" or "run the backup command"; nil for other requests.
    public static func runName(in command: String, language: AssistantLanguage) -> String? {
        if language == .english {
            guard let match = command.firstMatch(of: englishRun) else { return nil }
            let name = String(match.1).trimmingCharacters(in: .whitespaces)
            return name.isEmpty ? nil : name
        }
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        let folds = words.map { TurkishText.folded($0).replacingOccurrences(of: " ", with: "") }
        guard words.count >= 3 else { return nil }
        for index in 1..<(words.count - 1)
        where commandWords.contains(where: folds[index].hasPrefix) && runStems.contains(where: folds[index + 1].hasPrefix) {
            var start = 0
            while start < index, leadingFillers.contains(folds[start]) { start += 1 }
            let name = words[start..<index].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'’,."))
            return name.isEmpty ? nil : name
        }
        return nil
    }

    /// "Komutlarım neler", "hangi komutlarım var"; "list my commands". Only the user's own commands: "hangi komutları
    /// biliyorsun" asks about Bilge.
    public static func asksForList(_ command: String, language: AssistantLanguage) -> Bool {
        let words = Set(TurkishText.folded(command).split(separator: " ").map(String.init))
        if language == .english {
            return words.contains("commands") && (words.contains("my") || words.contains("custom"))
                && !words.isDisjoint(with: englishListCues)
        }
        return !words.isDisjoint(with: myCommands) && !words.isDisjoint(with: listCues)
    }

    /// The configured name meant, even when "komutunu" or "command" is said along with it.
    public static func bestMatch(_ spoken: String, in names: [String]) -> String? {
        PhraseMatcher.bestMatch(for: nameWords(spoken), in: names)
    }

    /// Whether `spoken` is `name` itself and no other configured name: "sunucu" only resembles "sunucuyu kapat".
    public static func namesExactly(_ spoken: String, name: String, names: [String]) -> Bool {
        let said = TurkishText.folded(nameWords(spoken))
        return TurkishText.folded(name) == said && names.filter { TurkishText.folded($0) == said }.count == 1
    }

    private static func nameWords(_ spoken: String) -> String {
        let words = spoken.split(whereSeparator: \.isWhitespace)
            .filter { word in !commandWords.contains(where: TurkishText.folded(String(word)).hasPrefix) }
        return words.isEmpty ? spoken : words.joined(separator: " ")
    }
}

/// A command line as typed in the settings, split the way a POSIX shell splits words: quotes group words, a backslash
/// escapes the next character outside single quotes. Nothing else of a shell applies.
public enum CommandLineText {
    public enum SplitError: Error, Equatable {
        case unclosedQuote
    }

    public static func split(_ line: String) throws -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for character in line {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            switch (quote, character) {
            case ("'", "'"), ("\"", "\""):
                quote = nil
            case ("'", _):
                current.append(character)
            case ("\"", "\\"), (nil, "\\"):
                escaped = true
                inWord = true
            case ("\"", _):
                current.append(character)
            case (nil, "'"), (nil, "\""):
                quote = character
                inWord = true
            case (nil, _) where character.isWhitespace:
                if inWord { words.append(current) }
                current = ""
                inWord = false
            default:
                current.append(character)
                inWord = true
            }
        }
        guard quote == nil, !escaped else { throw SplitError.unclosedQuote }
        if inWord { words.append(current) }
        return words
    }

    /// The words back as one line that `split` turns into the same words. "~" is left bare: Bilge opens it at the start
    /// of any word, quoted or not, and a quoted one would read as a literal tilde.
    public static func join(_ words: [String]) -> String {
        words.map { word in
            guard word.isEmpty || word.contains(where: { $0.isWhitespace || "'\"\\$`!*?;&|<>(){}[]#".contains($0) }) else {
                return word
            }
            return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        .joined(separator: " ")
    }
}
