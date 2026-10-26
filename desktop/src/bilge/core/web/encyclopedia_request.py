"""Encyclopedic questions ("Atatürk kimdir", "fotosentez nedir", "Mars hakkında bilgi ver", "who was Ada Lovelace")
and the short summary Wikipedia gives for them. Questions about now (the weather, a price, the time) or about the
assistant are not encyclopedic, whatever their wording."""

import re
from dataclasses import dataclass
from typing import Any

from bilge.core import text

_PUNCTUATION = re.compile(r"[?!.,;:\"“”]+")
_TURKISH_ENDINGS = (("kimdir",), ("kimdi",), ("nedir",), ("ne", "demek"), ("ne", "demektir"), ("nerededir",))
_TURKISH_ABOUT = ("bilgi", "biliyorsun", "anlat", "anlatir", "anlatsana")
_TURKISH_FILLERS = frozenset({"bana", "peki", "acaba", "bilge", "kisaca", "kisa"})
_ENGLISH_OPENINGS = (
    ("who", "is"), ("who", "was"), ("who", "were"), ("who", "are"), ("whos",), ("what", "is"), ("what", "was"),
    ("what", "are"), ("whats",), ("tell", "me", "about"), ("what", "do", "you", "know", "about"),
)  # fmt: skip
_ENGLISH_FILLERS = frozenset({"a", "an", "the"})
# Folded words that make a question about now, a price or the assistant rather than an encyclopedia entry.
_TURKISH_CURRENT = frozenset({
    "hava", "havalar", "saat", "bugun", "bugunku", "yarin", "dun", "simdi", "haber", "haberler", "kur", "kuru",
    "sen", "senin", "sana", "seni", "ben", "benim", "beni", "adin", "adim", "bu", "su", "sicaklik", "skor",
})  # fmt: skip
_TURKISH_CURRENT_STEMS = ("fiyat", "ezan", "vakit", "vakti")
_ENGLISH_CURRENT = frozenset({
    "weather", "time", "date", "today", "tomorrow", "yesterday", "now", "price", "prices", "rate", "news", "you",
    "your", "yours", "my", "me", "i", "this", "that", "it", "temperature", "score", "forecast",
})  # fmt: skip


# Words that put a whole question about now, even when it isn't worded like one of the above.
_TURKISH_NOW = frozenset({"hava", "havalar", "saat", "bugun", "bugunku", "yarin", "simdi", "haber", "haberler", "kur"})
_ENGLISH_NOW = frozenset({"weather", "time", "today", "tomorrow", "now", "price", "prices", "rate", "news", "forecast",
                          "temperature"})  # fmt: skip


@dataclass(frozen=True)
class Summary:
    title: str
    description: str
    extract: str
    disambiguation: bool


def subject(command: str, english: bool) -> str | None:
    """What the question asks about, in the words said ("Mustafa Kemal Atatürk"), or None when it isn't one."""
    words = _PUNCTUATION.sub(" ", command).split()
    folded = [text.folded(word) for word in words]
    found = _english(words, folded) if english else _turkish(words, folded)
    if not found:
        return None
    asked = [text.folded(w) for w in found]
    current = _ENGLISH_CURRENT if english else _TURKISH_CURRENT
    if any(w in current or (not english and w.startswith(_TURKISH_CURRENT_STEMS)) for w in asked):
        return None
    return " ".join(found)


def asks_about_now(command: str, english: bool) -> bool:
    words = text.folded(command).split()
    if english:
        return any(w in _ENGLISH_NOW for w in words)
    return any(w in _TURKISH_NOW or w.startswith(_TURKISH_CURRENT_STEMS) for w in words)


def _turkish(words: list[str], folded: list[str]) -> list[str]:
    start = 0
    while start < len(words) and folded[start] in _TURKISH_FILLERS:
        start += 1
    for ending in _TURKISH_ENDINGS:
        if len(folded) - start > len(ending) and tuple(folded[-len(ending) :]) == ending:
            return words[start : -len(ending)]
    if "hakkinda" in folded[start:]:
        at = folded.index("hakkinda", start)
        if at > start and any(w.startswith(_TURKISH_ABOUT) for w in folded[at + 1 :]):
            return words[start:at]
    return []


def _english(words: list[str], folded: list[str]) -> list[str]:
    for opening in _ENGLISH_OPENINGS:
        if tuple(folded[: len(opening)]) == opening and len(folded) > len(opening):
            rest = words[len(opening) :]
            while rest and text.folded(rest[0]) in _ENGLISH_FILLERS:
                rest = rest[1:]
            return rest
    return []


def from_summary(data: Any) -> Summary | None:
    """The REST /page/summary answer; None for anything but an article or a disambiguation page."""
    if not isinstance(data, dict) or data.get("type") not in ("standard", "disambiguation"):
        return None
    extract = str(data.get("extract") or "").strip()
    title = str(data.get("title") or "").strip()
    if not extract or not title:
        return None
    return Summary(title, str(data.get("description") or "").strip(), extract, data["type"] == "disambiguation")


def from_opensearch(data: Any) -> list[str]:
    """Titles from the opensearch answer: [query, [titles], [descriptions], [links]]."""
    if not isinstance(data, list) or len(data) < 2 or not isinstance(data[1], list):
        return []
    return [str(title) for title in data[1] if isinstance(title, str) and title.strip()]
