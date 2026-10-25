"""Which days a question about the calendar covers, from its own words: one day ("cuma ne var", "haftaya pazartesi",
"on November 15"), the coming seven days ("bu hafta") or next week from Monday ("önümüzdeki hafta", "next week")."""

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum

from bilge.core.text import folded
from bilge.core.tools import english_time_parser, relative_day_parser

DAYS_IN_WEEK = 7
_TURKISH_THIS_WEEK = (("bu", "hafta"), ("bu", "haftaki"), ("hafta", "boyunca"))
_ENGLISH_NEXT_WEEK = (("next", "week"),)
_ENGLISH_THIS_WEEK = (("this", "week"),)
_TURKISH_DAY_WORDS = ("bugun", "yarin", "obur", "ertesi")


class Kind(StrEnum):
    DAY = "day"
    THIS_WEEK = "thisWeek"
    NEXT_WEEK = "nextWeek"


@dataclass(frozen=True)
class Span:
    kind: Kind
    # Days from today to the first day covered.
    first: int
    days: int


def span(command: str, now: datetime, english: bool) -> Span | None:
    words = folded(command).split()
    names_day = (
        english_time_parser.day_offset(command, now) is not None
        if english
        else any(relative_day_parser.weekday_of(w) is not None or w.startswith(_TURKISH_DAY_WORDS) for w in words)
    )
    next_week = _ENGLISH_NEXT_WEEK if english else relative_day_parser.NEXT_WEEK_WORDS
    if not names_day and _has_phrase(words, next_week):
        return Span(Kind.NEXT_WEEK, DAYS_IN_WEEK - now.weekday(), DAYS_IN_WEEK)
    if not names_day and _has_phrase(words, _ENGLISH_THIS_WEEK if english else _TURKISH_THIS_WEEK):
        return Span(Kind.THIS_WEEK, 0, DAYS_IN_WEEK)
    day = english_time_parser.day_offset(command, now) if english else relative_day_parser.day_offset(command, now)
    return Span(Kind.DAY, day, 1) if day is not None else None


def _has_phrase(words: list[str], phrases: tuple[tuple[str, ...], ...]) -> bool:
    return any(tuple(words[i : i + len(p)]) == p for p in phrases for i in range(len(words) - len(p) + 1))
