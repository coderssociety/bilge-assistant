/// Decides whether speech heard while the assistant is talking is the user cutting in.
/// Echo cancellation is never perfect, so words the assistant is currently saying are removed
/// before looking for the wake phrase or a stop word.
public struct BargeInDetector: Sendable {
    public enum Decision: Sendable, Equatable {
        case none
        case stop
        case command(String)
    }

    private static let turkishStopWords: Set<String> = [
        "dur", "durdur", "sus", "yeter", "kes", "tamam", "iptal", "hayir", "bekle", "stop", "artik",
    ]
    private static let englishStopWords: Set<String> = [
        "stop", "quiet", "enough", "cancel", "wait", "hush", "silence", "okay", "ok", "no", "please", "now",
    ]
    private static let maxStopUtteranceWords = 4

    public let matcher: WakePhraseMatcher
    private let stopWords: Set<String>

    public init(matcher: WakePhraseMatcher, language: AssistantLanguage = .turkish) {
        self.matcher = matcher
        stopWords = language == .english ? Self.englishStopWords : Self.turkishStopWords
    }

    public func evaluate(heard: String, speaking reply: String) -> Decision {
        let echoWords = Set(TurkishText.folded(reply).split(separator: " ").map(String.init))
        let originalWords = heard.split(whereSeparator: \.isWhitespace).map(String.init)
        // Drop every word the assistant is saying right now — its own "Tamam" or "Ben Bilge" must
        // not cut it off. The user's words that differ from the reply are what remains.
        let remaining = originalWords.filter { word in
            let key = TurkishText.folded(word)
            return !key.isEmpty && !echoWords.contains(key)
        }
        guard !remaining.isEmpty else { return .none }

        let text = remaining.joined(separator: " ")
        if let match = matcher.match(text) {
            let rest = TurkishText.folded(match.command).split(separator: " ").map(String.init)
            if rest.isEmpty || rest.allSatisfy(stopWords.contains) { return .stop }
            return .command(match.command)
        }
        let keys = remaining.map { TurkishText.folded($0) }
        if keys.count <= Self.maxStopUtteranceWords, keys.contains(where: Self.isStop(in: stopWords)) { return .stop }
        return .none
    }

    /// Filler words such as "artık" or "please" end a stop only together with a real stop word.
    private static func isStop(in words: Set<String>) -> (String) -> Bool {
        { words.contains($0) && !fillerOnly.contains($0) }
    }

    private static let fillerOnly: Set<String> = ["artik", "please", "now"]
}
