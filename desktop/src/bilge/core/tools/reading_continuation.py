"""Reading a long text in parts: "devamını oku", "devam et", "read on" go on from where the last document, page or
story stopped instead of reading its start again."""

from dataclasses import dataclass, replace
from datetime import datetime, timedelta

from bilge.core.text import folded

# How long "devamını oku" still means the text just read.
CONTINUATION_WINDOW = timedelta(minutes=10)
# A part ends at a space within this many characters of its limit, so no word is cut in two.
_WORD_SLACK = 200
_FILLERS = frozenset({"bilge", "lutfen", "please", "peki", "hadi", "tamam", "ok", "okay", "then", "and", "ve"})
_PHRASES = frozenset({
    "devam", "devam et", "devam eder misin", "devami", "devamini", "devami ne", "devami var mi", "sonrasi",
    "sonrasi ne", "read on", "continue", "continue reading", "keep reading", "go on", "read more", "keep going",
    "what comes next", "whats next",
})  # fmt: skip
_OPENERS = ("devamini", "sonrasini", "kalanini", "geri kalanini")


def asks_to_continue(command: str) -> bool:
    words = [w for w in folded(command).split() if w not in _FILLERS]
    phrase = " ".join(words)
    return phrase in _PHRASES or phrase.startswith(_OPENERS)


@dataclass(frozen=True)
class Reading:
    title: str
    text: str
    size: int
    # Where the next part starts, and how many parts were read.
    offset: int
    parts: int
    at: datetime


@dataclass(frozen=True)
class Part:
    title: str
    text: str
    number: int
    has_more: bool


def first(title: str, text: str, size: int, at: datetime) -> tuple[Part, Reading]:
    return following(Reading(title, text, size, 0, 0, at), at)


def following(reading: Reading, at: datetime) -> tuple[Part, Reading]:
    """The next part, and the reading moved past it; an empty part once the end was reached."""
    end = _cut(reading.text, reading.offset, reading.size)
    part = Part(reading.title, reading.text[reading.offset : end].strip(), reading.parts + 1, end < len(reading.text))
    return part, replace(reading, offset=end, parts=reading.parts + 1, at=at)


def is_recent(reading: Reading | None, at: datetime) -> bool:
    return reading is not None and at - reading.at < CONTINUATION_WINDOW


def _cut(text: str, start: int, size: int) -> int:
    end = start + size
    if end >= len(text):
        return len(text)
    space = text.rfind(" ", max(start, end - _WORD_SLACK), end)
    return space if space > start else end
