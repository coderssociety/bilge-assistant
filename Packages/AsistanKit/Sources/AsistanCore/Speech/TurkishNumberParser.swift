import Foundation

/// Rewrites spelled-out Turkish numbers as digits before text reaches the language model, which is
/// unreliable at compound numbers ("üç yüz yirmi" became 300). Ambiguous words are only converted
/// in an unmistakably numeric context: "bir" (also "a"), "on" with a suffix ("onu" = "it"), "yüz" ("face").
public enum TurkishNumberParser {
    private static let words: [String: Int] = [
        "sıfır": 0, "bir": 1, "iki": 2, "üç": 3, "dört": 4, "dörd": 4, "beş": 5, "altı": 6, "yedi": 7,
        "sekiz": 8, "dokuz": 9, "on": 10, "yirmi": 20, "otuz": 30, "kırk": 40, "elli": 50, "altmış": 60,
        "yetmiş": 70, "seksen": 80, "doksan": 90, "yüz": 100, "bin": 1000, "milyon": 1_000_000,
        "milyar": 1_000_000_000, "trilyon": 1_000_000_000_000,
    ]
    /// Case, possessive and ordinal endings that follow numbers. Deliberately excludes "na/nda/ne/nde",
    /// which turn "altı" into "altına/altında" (under it).
    private static let suffixes: [String] = [
        "sını", "sini", "sunu", "sünü", "nın", "nin", "nun", "nün", "ıncı", "inci", "uncu", "üncü", "ncı", "nci", "ncu", "ncü",
        "lık", "lik", "luk", "lük", "yla", "yle", "dan", "den", "tan", "ten", "dır", "dir", "dur", "dür",
        "tır", "tir", "tur", "tür", "şar", "şer", "da", "de", "ta", "te", "ya", "ye", "yı", "yi", "yu", "yü",
        "ın", "in", "un", "ün", "sı", "si", "su", "sü", "la", "le", "ar", "er", "a", "e", "ı", "i", "u", "ü",
    ]
    private static let unitWords: Set<String> = [
        "dakika", "dakikalık", "saniye", "saniyelik", "saat", "saatlik", "gün", "günlük", "hafta", "ay", "yıl",
        "kez", "kere", "tane", "adet", "kişi", "lira", "dolar", "avro", "euro", "derece", "kilo", "metre", "litre", "sayfa",
    ]
    private static let ambiguous: Set<String> = ["bir", "on", "yüz"]

    private struct NumberToken {
        let value: Int
        let suffix: String
        let stem: String
    }

    public static func digitize(_ text: String) -> String {
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var index = 0
        while index < tokens.count {
            let run = numberRun(in: tokens, from: index)
            guard !run.isEmpty, isUnambiguous(run, tokens: tokens, start: index) else {
                output.append(tokens[index])
                index += 1
                continue
            }
            let last = run[run.count - 1]
            let trailing = trailingPunctuation(of: tokens[index + run.count - 1])
            output.append(String(value(of: run)) + (last.suffix.isEmpty ? "" : "'" + last.suffix) + trailing)
            index += run.count
        }
        return output.joined(separator: " ")
    }

    /// Longest sequence of number words; only the final word may carry a suffix.
    private static func numberRun(in tokens: [String], from start: Int) -> [NumberToken] {
        var run: [NumberToken] = []
        var index = start
        while index < tokens.count, let token = parse(tokens[index]) {
            if let previous = run.last, !canFollow(token.value, previous.value) { break }
            run.append(token)
            index += 1
            if !token.suffix.isEmpty || !trailingPunctuation(of: tokens[index - 1]).isEmpty { break }
        }
        return run
    }

    private static func parse(_ raw: String) -> NumberToken? {
        let core = TurkishText.lowercased(String(raw.dropLast(trailingPunctuation(of: raw).count)))
        guard !core.isEmpty, core != "yüzde" else { return nil }
        if let value = words[core] { return NumberToken(value: value, suffix: "", stem: core) }
        for (stem, value) in words where core.hasPrefix(stem) {
            let rest = String(core.dropFirst(stem.count)).replacingOccurrences(of: "'", with: "")
            if suffixes.contains(rest) { return NumberToken(value: value, suffix: rest, stem: stem) }
        }
        return nil
    }

    /// Rejects "bir iki" (counting) or "beş on" style sequences that are not one number.
    private static func canFollow(_ next: Int, _ previous: Int) -> Bool {
        if next >= 100 { return true }
        if previous >= 100 { return true }
        return previous >= 10 && previous % 10 == 0 && next < 10
    }

    private static func isUnambiguous(_ run: [NumberToken], tokens: [String], start: Int) -> Bool {
        guard run.count == 1, ambiguous.contains(run[0].stem) else { return true }
        let previous = start > 0 ? TurkishText.lowercased(tokens[start - 1]) : ""
        let next = start + 1 < tokens.count ? TurkishText.normalized(tokens[start + 1]) : ""
        let numericContext = previous == "saat" || unitWords.contains(next)
        switch run[0].stem {
        case "on": return run[0].suffix.isEmpty || numericContext
        default: return numericContext
        }
    }

    private static func value(of run: [NumberToken]) -> Int {
        var total = 0
        var current = 0
        for token in run {
            switch token.value {
            case ..<100: current += token.value
            case 100: current = max(current, 1) * 100
            default:
                total += max(current, 1) * token.value
                current = 0
            }
        }
        return total + current
    }

    private static func trailingPunctuation(of token: String) -> String {
        String(token.reversed().prefix(while: { $0.isPunctuation && $0 != "'" && $0 != "’" }).reversed())
    }
}
