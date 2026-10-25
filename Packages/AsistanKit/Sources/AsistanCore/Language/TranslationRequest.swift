import Foundation

/// A language Bilge can speak a translation in: one the Supertonic-3 voice knows.
public struct SpeechLanguage: Equatable, Sendable {
    /// ISO 639-1, as the voice takes it.
    public let code: String
    public let turkishName: String
    public let englishName: String

    public func name(in language: AssistantLanguage) -> String {
        language == .turkish ? turkishName : englishName
    }
}

/// The language a request wants what is read translated into: "İngilizce maili Türkçe oku", "bunu Fransızcaya
/// çevir", "read my email in German". Only the language it is to be read in counts, not the one the text is in.
public enum TranslationRequest {
    private static let languages: [(turkish: String, english: String, language: SpeechLanguage)] = [
        ("turkce", "turkish", .init(code: "tr", turkishName: "Türkçe", englishName: "Turkish")),
        ("ingilizce", "english", .init(code: "en", turkishName: "İngilizce", englishName: "English")),
        ("fransizca", "french", .init(code: "fr", turkishName: "Fransızca", englishName: "French")),
        ("almanca", "german", .init(code: "de", turkishName: "Almanca", englishName: "German")),
        ("ispanyolca", "spanish", .init(code: "es", turkishName: "İspanyolca", englishName: "Spanish")),
        ("italyanca", "italian", .init(code: "it", turkishName: "İtalyanca", englishName: "Italian")),
        ("portekizce", "portuguese", .init(code: "pt", turkishName: "Portekizce", englishName: "Portuguese")),
        ("felemenkce", "dutch", .init(code: "nl", turkishName: "Felemenkçe", englishName: "Dutch")),
        ("hollandaca", "dutch", .init(code: "nl", turkishName: "Felemenkçe", englishName: "Dutch")),
        ("rusca", "russian", .init(code: "ru", turkishName: "Rusça", englishName: "Russian")),
        ("arapca", "arabic", .init(code: "ar", turkishName: "Arapça", englishName: "Arabic")),
        ("japonca", "japanese", .init(code: "ja", turkishName: "Japonca", englishName: "Japanese")),
        ("korece", "korean", .init(code: "ko", turkishName: "Korece", englishName: "Korean")),
        ("yunanca", "greek", .init(code: "el", turkishName: "Yunanca", englishName: "Greek")),
        ("lehce", "polish", .init(code: "pl", turkishName: "Lehçe", englishName: "Polish")),
        ("ukraynaca", "ukrainian", .init(code: "uk", turkishName: "Ukraynaca", englishName: "Ukrainian")),
        ("isvecce", "swedish", .init(code: "sv", turkishName: "İsveççe", englishName: "Swedish")),
        ("danca", "danish", .init(code: "da", turkishName: "Danca", englishName: "Danish")),
        ("fince", "finnish", .init(code: "fi", turkishName: "Fince", englishName: "Finnish")),
        ("cekce", "czech", .init(code: "cs", turkishName: "Çekçe", englishName: "Czech")),
        ("romence", "romanian", .init(code: "ro", turkishName: "Romence", englishName: "Romanian")),
        ("bulgarca", "bulgarian", .init(code: "bg", turkishName: "Bulgarca", englishName: "Bulgarian")),
        ("macarca", "hungarian", .init(code: "hu", turkishName: "Macarca", englishName: "Hungarian")),
        ("hintce", "hindi", .init(code: "hi", turkishName: "Hintçe", englishName: "Hindi")),
        ("endonezce", "indonesian", .init(code: "id", turkishName: "Endonezce", englishName: "Indonesian")),
        ("vietnamca", "vietnamese", .init(code: "vi", turkishName: "Vietnamca", englishName: "Vietnamese")),
    ]
    /// "Türkçeye", "Fransızcaya": the dative names where the text goes; "Türkçesini oku": its version in that language.
    private static let targetEndings: Set<String> = ["ye", "ya", "e", "a", "si", "sini", "sine", "siyle", "yle", "la", "le"]
    /// The word after a bare language name that makes it the one to read in: "Türkçe oku", "Fransızca olarak".
    private static let readingWords = ["olarak", "oku", "cevir", "anlat", "soyle", "seslendir", "konus", "yaz", "ozetle",
                                       "aktar", "dil"]
    /// What after a reading word makes it describe the text instead: "İngilizce yazılmış", "yazılan", "konuşulan",
    /// "konuşan", "okunan", "yazdığı".
    private static let passiveStarts = ["il", "ul", "n"]
    private static let participleEndings: Set<String> = ["an", "en", "yan", "yen"]
    private static let participleStarts = ["dig", "tig", "dug", "tug", "mis", "mus"]
    /// "Fransızca de" (say it in French); "da"/"de" is otherwise "too": "Almanca da biliyor musun".
    private static let sayWord = "de"
    private static let tooWords: Set<String> = ["de", "da"]
    /// "Lehçe" is also "dialect" ("Karadeniz lehçesini anlat"): Polish only as "Lehçeye çevir" or "Lehçe oku".
    private static let dialectStem = "lehce"
    private static let datives: Set<String> = ["ye", "ya"]
    private static let translationVerbs = ["cevir", "tercume"]
    private static let englishCues: Set<String> = ["in", "into", "to"]

    public static func language(code: String) -> SpeechLanguage? {
        languages.first { $0.language.code == code }?.language
    }

    /// The language a single folded word names: "almanca", "turkceden", "german"; endings only in Turkish.
    static func language(inWord word: String, endings: Set<String>, english: Bool) -> SpeechLanguage? {
        if english { return languages.first { $0.english == word }?.language }
        return languages.first { entry in
            word.hasPrefix(entry.turkish) && endings.contains(String(word.dropFirst(entry.turkish.count)))
        }?.language
    }

    public static func target(in command: String) -> SpeechLanguage? {
        let words = TurkishText.folded(command).split { !$0.isLetter }.map(String.init)
        var found: SpeechLanguage?
        for (index, word) in words.enumerated() {
            let next = index + 1 < words.count ? words[index + 1] : ""
            let afterNext = index + 2 < words.count ? words[index + 2] : ""
            let previous = index > 0 ? words[index - 1] : ""
            for entry in languages {
                if word == entry.english, englishCues.contains(previous) {
                    found = entry.language
                } else if word.hasPrefix(entry.turkish) {
                    let ending = String(word.dropFirst(entry.turkish.count))
                    let readsIn = ending.isEmpty && (isReadingWord(next) || (next == sayWord && afterNext.isEmpty)
                        || (tooWords.contains(next) && isReadingWord(afterNext)))
                    let isTarget = entry.turkish == dialectStem
                        ? readsIn || (datives.contains(ending) && translationVerbs.contains(where: next.hasPrefix))
                        : readsIn || targetEndings.contains(ending)
                    if isTarget { found = entry.language }
                }
            }
        }
        return found
    }

    private static func isReadingWord(_ word: String) -> Bool {
        readingWords.contains { stem in
            guard word.hasPrefix(stem) else { return false }
            let rest = String(word.dropFirst(stem.count))
            return !participleEndings.contains(rest) && !(passiveStarts + participleStarts).contains(where: rest.hasPrefix)
        }
    }
}
