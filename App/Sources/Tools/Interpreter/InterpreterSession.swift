import AsistanCore
import Foundation

/// "Tercüman modu": while it is on, everything said is translated into the pair's other language and spoken in
/// it, until the stop phrase or two minutes of silence.
@MainActor
final class InterpreterSession {
    static let window: TimeInterval = 120

    private(set) var pair: InterpreterPair?
    var isActive: Bool { pair != nil }

    func begin(_ pair: InterpreterPair) {
        self.pair = pair
    }

    func end() {
        pair = nil
    }

    /// The language heard and the one to answer in. Speech whose language is unknown or outside the pair is
    /// taken as the assistant's own language when that is in the pair, else as the pair's first.
    func direction(heard code: String?, assistant: AssistantLanguage) -> (source: SpeechLanguage, target: SpeechLanguage)? {
        guard let pair else { return nil }
        let source = code.flatMap(pair.language(code:)) ?? pair.language(code: assistant.code) ?? pair.first
        guard let target = pair.counterpart(of: source.code) else { return nil }
        return (source, target)
    }
}
