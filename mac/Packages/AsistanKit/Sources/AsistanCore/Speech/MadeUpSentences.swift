import Foundation

/// Sentences Whisper makes up when it hears no words (silence, breathing, a fan, music). They come from the subtitles
/// it was trained on, so they are the closing lines of videos: nobody says them to an assistant.
///
/// Only whole sentences are dropped, and only these; "teşekkürler" and "thank you" stay, since people do say those.
public enum MadeUpSentences {
    /// Folded (lowercase, no Turkish letters, no punctuation) whole sentences.
    private static let sentences: Set<String> = [
        "altyazi m k", "alt yazi m k", "altyazi mk", "altyazilar m k",
        "izlediginiz icin tesekkur ederim", "izlediginiz icin tesekkurler", "izlediginiz icin tesekkur ederiz",
        "abone olmayi unutmayin", "kanalima abone olmayi unutmayin", "begenmeyi ve abone olmayi unutmayin",
        "videoyu begenmeyi ve abone olmayi unutmayin", "bir sonraki videoda gorusmek uzere",
        "bir sonraki videoda gorusuruz", "altyazilar amara org toplulugu tarafindan saglanmistir",
        "thanks for watching", "thank you for watching", "thanks for watching and see you next time",
        "thank you so much for watching", "please subscribe", "please like and subscribe",
        "don t forget to like and subscribe", "see you in the next video", "see you next time",
        "subtitles by the amara org community", "you",
    ]
    /// Credit lines with a name after them ("Subtitles by …").
    private static let prefixes = [
        "subtitles by ", "subtitled by ", "transcription by ", "transcribed by ", "translated by ", "captions by ",
    ]
    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]

    public static func isMadeUp(_ sentence: String) -> Bool {
        let key = TurkishText.folded(sentence)
        if sentences.contains(key) || prefixes.contains(where: key.hasPrefix) || key.contains("amara org") {
            return true
        }
        // The Turkish credit lines need the colon: "altyazı aç" is a request.
        let turkishCredit = /^\s*(alt ?yazı(lar)?|çeviri|çeviren)\s*:/
        return TurkishText.lowercased(sentence).firstMatch(of: turkishCredit) != nil
    }

    /// The transcript without the sentences Whisper invents; empty when nothing else was heard.
    public static func removed(from transcript: String) -> String {
        split(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
            .filter { !isMadeUp($0) }
            .joined(separator: " ")
    }

    /// Sentences end at ".", "!", "?" or "…" followed by a space, so "M.K." stays whole.
    private static func split(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        var previous: Character?
        for character in text {
            if character.isWhitespace, let previous, sentenceEnds.contains(previous) {
                sentences.append(current)
                current = ""
            } else if !(character.isWhitespace && current.isEmpty) {
                current.append(character)
            }
            previous = character
        }
        sentences.append(current)
        return sentences.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
