"""Note requests read from the words themselves: adding to an existing note ("alışveriş notuma süt ekle",
"toplantı notuna şunu ekle: …") and listing notes ("notlarım neler", "son notlarım"). The text to add is kept exactly
as the user said it."""

from dataclasses import dataclass

from bilge.core.language import AssistantLanguage
from bilge.core.text import folded


@dataclass(frozen=True)
class Addition:
    # The note's name as said, without the "notuma" word: "alışveriş".
    note: str
    text: str


_NOTE_WORDS = frozenset({"notuma", "notuna", "notumuza", "notlarima", "notlarina", "notunun", "notumun"})
# "Toplantı notunun sonuna ekle".
_END_WORDS = frozenset({"sonuna", "altina"})
_ADD_STEMS = ("ekle", "ilave", "kaydet")
_WRITE_VERBS = frozenset({"yaz", "yazar", "yazsana", "yazabilir", "yazin", "yaziver"})
_POINTERS = frozenset({"sunu", "bunu", "sunlari", "bunlari"})
_TEXT_ENDS = frozenset({"diye", "olarak"})
_LEADING_FILLERS = frozenset({"lutfen", "bilge", "benim", "bir", "please", "my", "the", "our"})
_QUESTION_PARTICLES = frozenset(
    {"mi", "mu", "misin", "musun", "misiniz", "musunuz", "lutfen", "hemen", "simdi", "please", "now"}
)
_EDGE_PUNCTUATION = "\"“”‘’'«».,!?;:… "

_ENGLISH_VERBS = frozenset({"add", "append", "put", "write", "jot"})
_ENGLISH_PLACES = frozenset({"to", "in", "into", "on", "onto"})

_PLURAL_NOTES = frozenset({"notlarim", "notlarimi", "notlar", "notlari", "notlarimiz"})
_LIST_CUES = frozenset({"neler", "ne", "listele", "hangi", "hangileri", "son", "say", "goster", "oku"})
_ENGLISH_LIST_CUES = frozenset({"list", "what", "which", "show", "recent", "latest", "last", "my"})
_ENGLISH_NOT_LIST = frozenset({"open", "about", "delete", "add"})


class _Words:
    """The words as said and folded side by side, so matching uses folded words and the result keeps the user's own
    spelling."""

    def __init__(self, command: str):
        self.raw = command.split()
        # "e-postasına" folds to one word.
        self.folded = [folded(word).replace(" ", "") for word in self.raw]

    @property
    def content_end(self) -> int:
        """One past the last word that is not a question particle or "lütfen"."""
        end = len(self.raw)
        while end > 0 and self.folded[end - 1] in _QUESTION_PARTICLES:
            end -= 1
        return end

    def text(self, start: int, end: int) -> str:
        return " ".join(self.raw[max(start, 0) : end]).strip(_EDGE_PUNCTUATION)


def addition(command: str, language: AssistantLanguage = AssistantLanguage.TURKISH) -> Addition | None:
    words = _Words(command)
    return _english_addition(words) if language is AssistantLanguage.ENGLISH else _turkish_addition(words)


def _turkish_addition(words: _Words) -> Addition | None:
    folds = words.folded
    note = next((i for i, word in enumerate(folds) if word in _NOTE_WORDS), None)
    if note is None:
        return None
    end = words.content_end
    verb = next((i for i in range(note + 1, max(note + 1, end)) if _is_add_verb(folds[i])), None)
    if verb is None:
        return None
    start = note + 2 if note + 1 < verb and folds[note + 1] in _END_WORDS else note + 1
    before = list(range(start, verb))
    while before and folds[before[0]] in _POINTERS:
        before.pop(0)
    while before and folds[before[-1]] in _TEXT_ENDS:
        before.pop()
    # "…notuna şunu ekle: …" puts the text after the verb; otherwise it sits between the note and the verb.
    chosen = before or list(range(verb + 1, end))
    if not chosen:
        return None
    return _addition(_name(words, 0, note), words.text(chosen[0], chosen[-1] + 1))


def _is_add_verb(word: str) -> bool:
    return word.startswith(_ADD_STEMS) or word in _WRITE_VERBS


def _english_addition(words: _Words) -> Addition | None:
    """ "Add milk to my shopping note", "add to my shopping note: eggs", "write in my meeting note that …"."""
    folds = words.folded
    verb = next((i for i, word in enumerate(folds) if word in _ENGLISH_VERBS), None)
    if verb is None:
        return None
    note = next((i for i in range(verb + 1, len(folds)) if folds[i] in ("note", "notes")), None)
    if note is None:
        return None
    place = next((i for i in range(note - 1, verb, -1) if folds[i] in _ENGLISH_PLACES), None)
    if place is None:
        return None
    end = words.content_end
    chosen = list(range(verb + 1, place))
    if chosen and folds[chosen[0]] == "down":
        chosen.pop(0)
    if not chosen:
        chosen = list(range(note + 1, end))
    while chosen and folds[chosen[0]] == "that":
        chosen.pop(0)
    if not chosen:
        return None
    return _addition(_name(words, place + 1, note), words.text(chosen[0], chosen[-1] + 1))


def _name(words: _Words, start: int, end: int) -> str:
    while start < end and words.folded[start] in _LEADING_FILLERS:
        start += 1
    return words.text(start, end)


def _addition(note: str, text: str) -> Addition | None:
    return Addition(note, text) if note and text else None


def asks_for_list(command: str, language: AssistantLanguage = AssistantLanguage.TURKISH) -> bool:
    """ "Notlarım neler", "son notlarım", "hangi notlarım var"; "list my notes". One note ("son notumu oku") or
    opening something ("notlarımı aç") is not a list."""
    words = set(folded(command).split())
    if language is AssistantLanguage.ENGLISH:
        return "notes" in words and bool(words & _ENGLISH_LIST_CUES) and not words & _ENGLISH_NOT_LIST
    return bool(words & _PLURAL_NOTES) and bool(words & _LIST_CUES)
