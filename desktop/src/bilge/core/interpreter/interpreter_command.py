"""Starting and ending interpreter mode by voice: "tercüman modunu aç: Türkçe ve İngilizce", "Almanca tercüme et",
"tercümanı kapat"; "start the interpreter for English and German", "interpret Spanish", "stop interpreting"."""

from bilge.core.interpreter.interpretation import LanguagePair
from bilge.core.language import AssistantLanguage
from bilge.core.text import folded
from bilge.core.translation_request import by_code, mentioned, target

_STOP_STEMS = ("kapat", "bitir", "durdur", "birak", "sonlandir")
_STOP_WORDS = frozenset({"kes", "stop", "off", "end", "exit", "quit", "close", "disable", "finish", "cancel"})
_START_STEMS = ("ac", "basla", "baslat", "calis")
_START_WORDS = frozenset({"ol", "olur", "yap", "start", "begin", "turn", "on", "enable", "be", "act"})
# "Almanca tercüme et": besides the language names, only these words, so "bu maili Almanca tercüme et" (translate
# that e-mail) is not taken for the mode.
_SHORT_FORM_WORDS = frozenset({"tercume", "et", "eder", "misin", "yap", "lutfen", "bana", "icin", "bilge", "ve"})
# A stop phrase is short; "tercümanı kapatmayı unutma, sonra konuşuruz" said to the other person is translated.
MAX_STOP_WORDS = 6


def _is_stop_word(word: str) -> bool:
    return word.startswith(_STOP_STEMS) or word in _STOP_WORDS


def _is_start_word(word: str) -> bool:
    return word.startswith(_START_STEMS) or word in _START_WORDS


def _mentions_mode(words: list[str]) -> bool:
    return any(word.startswith(("tercuman", "tercume", "interpret")) for word in words)


def is_start(command: str) -> bool:
    words = folded(command).split()
    if not _mentions_mode(words) or any(_is_stop_word(word) for word in words):
        return False
    if any(word.startswith(("tercuman", "interpret")) for word in words):
        # "Tercüman modu", "interpreter mode": the mode named on its own starts it too.
        return any(_is_start_word(word) for word in words) or bool(mentioned(command)) or len(words) <= 2
    # "Almancaya tercüme et" asks for something already said in German, not for the mode.
    if not mentioned(command) or target(command) is not None:
        return False
    names = {folded(language.turkish_name) for language in mentioned(command)}
    return all(word in names or word in _SHORT_FORM_WORDS or word.startswith("tercume") for word in words)


def is_stop(said: str) -> bool:
    words = folded(said).split()
    return 0 < len(words) <= MAX_STOP_WORDS and _mentions_mode(words) and any(_is_stop_word(word) for word in words)


def language_pair(command: str, language: AssistantLanguage) -> LanguagePair:
    """The two languages named; with one, the assistant's own language and that one; with none, Turkish and
    English."""
    named = mentioned(command)
    own = by_code(language.code)
    fallback = by_code("en" if language is AssistantLanguage.TURKISH else "tr")
    assert own is not None and fallback is not None
    if len(named) >= 2:
        return LanguagePair(named[0], named[1])
    if len(named) == 1 and named[0] != own:
        return LanguagePair(own, named[0])
    return LanguagePair(own, fallback)
