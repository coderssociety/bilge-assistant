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
# "Fransızca de": too short to match as a beginning. "da" only joins ("Almanca da biliyor musun"), and asks for the
# language only before a reading word ("Almanca da söyle").
_SHORT_READING_WORDS = frozenset({"de"})
_ALSO = frozenset({"da", "de"})
# "İngilizce yazılmış mail", "Almanca konuşan biri": the language the text is in, not one to read it in.
_PARTICIPLE_ENDINGS = ("an", "en", "mis", "mus", "digi", "dugu")
# "Lehçe" is also "dialect" ("Karadeniz lehçesini anlat"): Polish only when something is to be turned into it.
_AMBIGUOUS = frozenset({"lehce"})
_TRANSLATING = ("cevir", "tercume")
_ENGLISH_CUES = frozenset({"in", "into", "to"})
# "ingilizceden", "almancaya", "türkçesini".
_LONGEST_ENDING = 5


def by_code(code: str) -> SpeechLanguage | None:
    return next((language for *_, language in _LANGUAGES if language.code == code), None)


def mentioned(command: str) -> list[SpeechLanguage]:
    """Every language named, in the order said and once each, whatever case ending it has ("Türkçeden Almancaya")."""
    found: list[SpeechLanguage] = []
    words = text.folded(command).split()
    for index, word in enumerate(words):
        for turkish, english, language in _LANGUAGES:
            named = word == english or _turkish_ending(words, index, turkish) is not None
            if named and language not in found:
                found.append(language)
    return found


def _turkish_ending(words: list[str], index: int, turkish: str) -> str | None:
    """The case ending when words[index] is the Turkish name `turkish` ("almancaya" → "ya"), else None."""
    word = words[index]
    if not word.startswith(turkish) or len(word) - len(turkish) > _LONGEST_ENDING:
        return None
    ending = word[len(turkish) :]
    if turkish in _AMBIGUOUS:
        following = words[index + 1] if index + 1 < len(words) else ""
        return ending if ending in ("ye", "ya") and following.startswith(_TRANSLATING) else None
    return ending


def _asks_to_read(following: str, after: str) -> bool:
    if following in _ALSO:
        return not after or _asks_to_read(after, "")
    if following in _SHORT_READING_WORDS:
        return True
    return following.startswith(_READING_WORDS) and not following.endswith(_PARTICIPLE_ENDINGS)


def target(command: str) -> SpeechLanguage | None:
    words = [word for word in text.folded(command).split() if word.isalpha()]
    found = None
    for index, word in enumerate(words):
        following, after = (words[index + 1 : index + 3] + ["", ""])[:2]
        previous = words[index - 1] if index else ""
        for turkish, english, language in _LANGUAGES:
            if word == english and previous in _ENGLISH_CUES:
                found = language
                continue
            ending = _turkish_ending(words, index, turkish)
            if ending in _TARGET_ENDINGS or (ending == "" and _asks_to_read(following, after)):
                found = language
    return found
