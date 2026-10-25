"""The language a request wants what is read translated into: "İngilizce maili Türkçe oku", "bunu Fransızcaya çevir",
"read my email in German". Only the language it is to be read in counts, not the one the text is in."""

from dataclasses import dataclass

from bilge.core import text
from bilge.core.language import AssistantLanguage


@dataclass(frozen=True)
class SpeechLanguage:
    """A language Bilge can speak a translation in: one the Supertonic-3 voice knows."""

    # ISO 639-1, as the voice takes it.
    code: str
    turkish_name: str
    english_name: str

    def name(self, language: AssistantLanguage) -> str:
        return self.turkish_name if language is AssistantLanguage.TURKISH else self.english_name


_LANGUAGES = [
    ("turkce", "turkish", SpeechLanguage("tr", "Türkçe", "Turkish")),
    ("ingilizce", "english", SpeechLanguage("en", "İngilizce", "English")),
    ("fransizca", "french", SpeechLanguage("fr", "Fransızca", "French")),
    ("almanca", "german", SpeechLanguage("de", "Almanca", "German")),
    ("ispanyolca", "spanish", SpeechLanguage("es", "İspanyolca", "Spanish")),
    ("italyanca", "italian", SpeechLanguage("it", "İtalyanca", "Italian")),
    ("portekizce", "portuguese", SpeechLanguage("pt", "Portekizce", "Portuguese")),
    ("felemenkce", "dutch", SpeechLanguage("nl", "Felemenkçe", "Dutch")),
    ("hollandaca", "dutch", SpeechLanguage("nl", "Felemenkçe", "Dutch")),
    ("rusca", "russian", SpeechLanguage("ru", "Rusça", "Russian")),
    ("arapca", "arabic", SpeechLanguage("ar", "Arapça", "Arabic")),
    ("japonca", "japanese", SpeechLanguage("ja", "Japonca", "Japanese")),
    ("korece", "korean", SpeechLanguage("ko", "Korece", "Korean")),
    ("yunanca", "greek", SpeechLanguage("el", "Yunanca", "Greek")),
    ("lehce", "polish", SpeechLanguage("pl", "Lehçe", "Polish")),
    ("ukraynaca", "ukrainian", SpeechLanguage("uk", "Ukraynaca", "Ukrainian")),
    ("isvecce", "swedish", SpeechLanguage("sv", "İsveççe", "Swedish")),
    ("danca", "danish", SpeechLanguage("da", "Danca", "Danish")),
    ("fince", "finnish", SpeechLanguage("fi", "Fince", "Finnish")),
    ("cekce", "czech", SpeechLanguage("cs", "Çekçe", "Czech")),
    ("romence", "romanian", SpeechLanguage("ro", "Romence", "Romanian")),
    ("bulgarca", "bulgarian", SpeechLanguage("bg", "Bulgarca", "Bulgarian")),
    ("macarca", "hungarian", SpeechLanguage("hu", "Macarca", "Hungarian")),
    ("hintce", "hindi", SpeechLanguage("hi", "Hintçe", "Hindi")),
    ("endonezce", "indonesian", SpeechLanguage("id", "Endonezce", "Indonesian")),
    ("vietnamca", "vietnamese", SpeechLanguage("vi", "Vietnamca", "Vietnamese")),
]
# "Türkçeye", "Fransızcaya": the dative names where the text goes; "Türkçesini oku": its version in that language.
_TARGET_ENDINGS = frozenset({"ye", "ya", "e", "a", "si", "sini", "sine", "siyle", "yle", "la", "le"})
# The word after a bare language name that makes it the one to read in: "Türkçe oku", "Fransızca olarak".
_READING_WORDS = ("olarak", "oku", "cevir", "anlat", "soyle", "seslendir", "konus", "yaz", "ozetle", "aktar", "dil")
# "Fransızca de": too short to match as a beginning.
_SHORT_READING_WORDS = frozenset({"de", "da"})
_ENGLISH_CUES = frozenset({"in", "into", "to"})


def target(command: str) -> SpeechLanguage | None:
    words = [word for word in text.folded(command).split() if word.isalpha()]
    found = None
    for index, word in enumerate(words):
        following = words[index + 1] if index + 1 < len(words) else ""
        previous = words[index - 1] if index else ""
        for turkish, english, language in _LANGUAGES:
            if word == english and previous in _ENGLISH_CUES:
                found = language
            elif word.startswith(turkish):
                ending = word[len(turkish) :]
                reading = following in _SHORT_READING_WORDS or following.startswith(_READING_WORDS)
                if ending in _TARGET_ENDINGS or (not ending and reading):
                    found = language
    return found
