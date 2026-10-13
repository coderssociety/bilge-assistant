/// Decides whether speech heard while the assistant is talking is the user cutting in.
/// Echo cancellation is never perfect, so words the assistant is currently saying are removed
/// before looking for the wake phrase or a stop word.
public struct BargeInDetector: Sendable {
    public enum Decision: Sendable, Equatable {
        case none
        case stop
        case command(String)
    }

    private static let stopWords: Set<String> = [
        "dur", "durdur", "sus", "yeter", "kes", "tamam", "iptal", "hayir", "bekle", "stop",
    ]
    private static let maxStopUtteranceWords = 4

    public let matcher: WakePhraseMatcher

    public init(matcher: WakePhraseMatcher) {
        self.matcher = matcher
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
            if rest.isEmpty || rest.allSatisfy({ Self.stopWords.contains($0) || $0 == "artik" }) { return .stop }
            return .command(match.command)
        }
        let keys = remaining.map { TurkishText.folded($0) }
        if keys.count <= Self.maxStopUtteranceWords, keys.contains(where: Self.stopWords.contains) { return .stop }
        return .none
    }
}
