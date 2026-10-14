import Foundation

/// Rewrites model output into plain text for the synthesizer, in the assistant's language.
public enum SpokenText {
    public static func normalize(_ text: String, language: AssistantLanguage) -> String {
        switch language {
        case .turkish: TurkishSpeechNormalizer.normalize(text)
        case .english: EnglishSpeechNormalizer.normalize(text)
        }
    }

    /// Markdown and emoji, which conversation models add despite being told not to; TTS would read them out.
    public static func withoutMarkup(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?m)^\s*(#{1,6}|[-*•])\s+"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?<![\p{L}\d*_])([*_])(?=\S)(.+?)(?<=\S)\1(?![\p{L}\d*_])"#,
                                             with: "$2", options: .regularExpression)
        result = result.replacingOccurrences(of: #"[\p{Extended_Pictographic}\p{Regional_Indicator}\x{FE0F}\x{200D}\x{20E3}]+"#,
                                             with: "", options: .regularExpression)
        return result
    }
}
