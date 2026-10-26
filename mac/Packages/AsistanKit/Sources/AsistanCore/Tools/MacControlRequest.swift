/// What a routed Mac-control command asks for, read from its words so the tools never act on an
/// argument the model invented: Focus on or off, which power action, how much brightness, Bluetooth
/// on, off or its state, and how far to seek. nil means the words don't say.
public enum MacControlRequest {
    public enum Power: Sendable, Equatable { case restart, shutDown, logOut }
    public enum Change: Sendable, Equatable { case up(Int?), down(Int?), set(Int) }
    public enum Switch: Sendable, Equatable { case on, off, status }

    private static let turkishOnWords: Set<String> = ["ac", "acar", "acsana", "acin", "etkinlestir", "aktif", "baslat"]
    private static let turkishOffStems = ["kapat", "kapa", "bitir", "sonlandir", "devre"]
    private static let englishOnWords: Set<String> = ["on", "enable", "activate", "start"]
    private static let englishOffWords: Set<String> = ["off", "disable", "deactivate", "stop", "end"]
    private static let computerWords: Set<String> = [
        "bilgisayar", "bilgisayari", "mac", "maci", "macbook", "macbooku", "sistemi",
    ]
    private static let englishComputerWords: Set<String> = ["mac", "computer", "laptop", "system", "macbook", "imac"]
    private static let notTheComputer = ["ekran", "pencere", "uygulama", "sekme"]
    private static let upStems = ["artir", "arttir", "yukselt", "cogalt", "parlat"]
    private static let downStems = ["azalt", "dusur", "alcalt", "kis", "karart"]
    private static let setWords: Set<String> = ["yap", "getir", "ayarla", "cek", "indir", "cikar"]
    private static let englishUpWords: Set<String> = ["up", "increase", "raise", "brighter", "brighten", "higher"]
    private static let englishDownWords: Set<String> = ["down", "decrease", "lower", "dim", "dimmer", "darker", "reduce"]
    private static let questionParticles: Set<String> = ["mi", "mu", "mii"]
    private static let secondsPerMinute = 60
    private static let maxPercent = 100

    public static func focus(_ text: String, language: AssistantLanguage) -> Bool? {
        let words = words(text, language)
        if language == .english {
            let named = words.contains("focus") || words.contains("dnd") || words.contains("disturb")
            guard named else { return nil }
            if words.contains(where: englishOffWords.contains) { return false }
            return words.contains(where: englishOnWords.contains) ? true : nil
        }
        let named = words.contains("rahatsiz") || words.contains { $0.hasPrefix("odak") || $0.hasPrefix("odag") }
        guard named else { return nil }
        return toggle(words)
    }

    public static func power(_ text: String, language: AssistantLanguage) -> Power? {
        let words = words(text, language)
        if language == .english {
            let joined = " " + words.joined(separator: " ") + " "
            if [" log out ", " logout ", " sign out ", " log me out "].contains(where: joined.contains) { return .logOut }
            guard words.contains(where: englishComputerWords.contains) else { return nil }
            if words.contains("restart") || words.contains("reboot") { return .restart }
            let shutsDown = [" shut down ", " shutdown ", " power off ", " turn off ", " switch off "].contains(where: joined.contains)
            return shutsDown ? .shutDown : nil
        }
        if words.contains(where: { $0.hasPrefix("oturum") }),
           words.contains(where: { $0.hasPrefix("kapat") || $0.hasPrefix("cik") || $0.hasPrefix("sonlandir") }) {
            return .logOut
        }
        guard words.contains(where: computerWords.contains),
              !words.contains(where: { word in notTheComputer.contains(where: word.hasPrefix) }) else { return nil }
        if (words.contains("yeniden") && words.contains { $0.hasPrefix("baslat") }) || words.contains(where: { $0.hasPrefix("resetle") }) {
            return .restart
        }
        return words.contains(where: { $0.hasPrefix("kapat") }) ? .shutDown : nil
    }

    public static func brightness(_ text: String, language: AssistantLanguage) -> Change? {
        let words = words(text, language)
        let number = percent(in: words)
        if language == .english {
            if words.contains(where: ["max", "maximum", "full", "highest"].contains) { return .set(maxPercent) }
            if words.contains(where: ["minimum", "lowest"].contains) { return .set(0) }
            if words.contains(where: englishUpWords.contains) { return .up(number) }
            if words.contains(where: englishDownWords.contains) { return .down(number) }
            return number.map { .set($0) }
        }
        let joined = words.joined(separator: " ")
        if joined.contains("sonuna kadar") || joined.contains("en yuksek") || joined.contains("tam parlak") { return .set(maxPercent) }
        if joined.contains("en dusuk") || joined.contains("en az") { return .set(0) }
        if let number, words.contains(where: setWords.contains) { return .set(number) }
        if words.contains(where: { word in upStems.contains(where: word.hasPrefix) }) || words.contains(where: turkishOnWords.contains) {
            return .up(number)
        }
        return words.contains(where: { word in downStems.contains(where: word.hasPrefix) }) ? .down(number) : nil
    }

    public static func bluetooth(_ text: String, language: AssistantLanguage) -> Switch? {
        let words = words(text, language)
        if language == .english {
            if words.contains(where: englishOffWords.contains) { return .off }
            if words.contains(where: englishOnWords.contains) && words.first != "is" { return .on }
            return words.contains(where: ["is", "status", "state"].contains) ? .status : nil
        }
        if words.contains(where: questionParticles.contains) || words.contains(where: { $0.hasPrefix("durum") }) { return .status }
        return toggle(words).map { $0 ? .on : .off }
    }

    /// "30 saniye ileri sar" → 30, "iki dakika geri" → 120, "skip ahead 15 seconds" → 15.
    public static func seekSeconds(_ text: String, language: AssistantLanguage) -> Int? {
        let words = words(text, language)
        for (index, word) in words.enumerated() where index > 0 {
            let amount = words[index - 1] == "yarim" ? 0.5 : Double(words[index - 1])
            guard let amount else { continue }
            if word.hasPrefix("saniye") || word.hasPrefix("second") || word == "sn" || word.hasPrefix("sec") {
                return Int(amount)
            }
            if word.hasPrefix("dakika") || word.hasPrefix("minute") || word == "dk" || word == "min" {
                return Int(amount * Double(secondsPerMinute))
            }
        }
        return nil
    }

    private static func toggle(_ words: [String]) -> Bool? {
        if words.contains(where: { word in turkishOffStems.contains(where: word.hasPrefix) }) { return false }
        return words.contains(where: turkishOnWords.contains) ? true : nil
    }

    /// "yüzde 50", "50'ye", "50%"; clamped to 100.
    private static func percent(in words: [String]) -> Int? {
        let number = words.lazy.compactMap { word -> Int? in
            let digits = word.prefix(while: \.isNumber)
            return digits.isEmpty ? nil : Int(digits)
        }.first
        return number.map { min($0, maxPercent) }
    }

    private static func words(_ text: String, _ language: AssistantLanguage) -> [String] {
        let digitized = language == .turkish ? TurkishNumberParser.digitize(text) : text
        return TurkishText.folded(digitized).split(separator: " ").map(String.init)
    }
}
