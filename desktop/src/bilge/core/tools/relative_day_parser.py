"""Reads which day a Turkish request refers to ("yarın", "cuma", "haftaya çarşamba", "3 gün sonra", "15 Kasım'da")
as an offset from today. A bare weekday means its next occurrence; today's weekday means next week."""

import re
from datetime import date, datetime, tzinfo

from bilge.core.text import folded

_FIXED: tuple[tuple[str, int], ...] = (
    ("yarindan sonra", 2), ("obur gun", 2), ("ertesi gun", 1), ("yarin", 1), ("bugun", 0),
)  # fmt: skip
# Calendar weekday numbers (1 = Sunday), as in Swift's Calendar.
_WEEKDAYS: dict[str, int] = {
    "pazar": 1,
    "pazartesi": 2,
    "sali": 3,
    "carsamba": 4,
    "persembe": 5,
    "cuma": 6,
    "cumartesi": 7,
}
# Case endings a day name takes ("cumaya", "salıdan", "perşembeki"), folded. "Pazar" is also the market, so
# "pazara gitmek" or "pazarda" never mean Sunday; only the bare word does.
_ENDINGS = frozenset({
    "ya", "ye", "da", "de", "ta", "te", "dan", "den", "tan", "ten", "yi", "ki", "si", "nin", "ndan", "nden",
    "leri", "lari",
})  # fmt: skip
_MARKET_DAY = "pazar"
_MONTHS: dict[str, int] = {
    "ocak": 1, "subat": 2, "mart": 3, "nisan": 4, "mayis": 5, "haziran": 6, "temmuz": 7, "agustos": 8, "eylul": 9,
    "ekim": 10, "kasim": 11, "aralik": 12,
}  # fmt: skip
_DAYS_LATER = re.compile(r"\b(\d+) gun sonra")
_WEEKS_LATER = re.compile(r"\b(\d+) hafta sonra")
_DATE = re.compile(r"\b(\d{1,2}) (" + "|".join(_MONTHS) + r")\w*")
NEXT_WEEK_WORDS = (("haftaya",), ("gelecek", "hafta"), ("onumuzdeki", "hafta"))
DAYS_IN_WEEK = 7


def calendar_weekday(moment: datetime) -> int:
    """1 = Sunday ... 7 = Saturday."""
    return moment.isoweekday() % 7 + 1


def weekday_of(word: str) -> int | None:
    """The calendar weekday a folded word names, with its ending: "cumaya" → 6, "pazara" → None."""
    for stem, number in _WEEKDAYS.items():
        if word == stem or (stem != _MARKET_DAY and word.startswith(stem) and word[len(stem) :] in _ENDINGS):
            return number
    return None


def day_offset(text: str, now: datetime, tz: tzinfo | None = None) -> int | None:
    """`tz` plays the role of Swift's calendar time zone; without it `now` is read as given."""
    folded_text = folded(text)
    local = now.astimezone(tz) if tz is not None else now
    for pattern, days in ((_DAYS_LATER, 1), (_WEEKS_LATER, DAYS_IN_WEEK)):
        found = pattern.search(folded_text)
        if found is not None:
            return int(found.group(1)) * days
    absolute = _date_offset(folded_text, local.date())
    if absolute is not None:
        return absolute
    words = folded_text.split()
    for index, word in enumerate(words):
        weekday = weekday_of(word)
        if weekday is None:
            continue
        offset = (weekday - calendar_weekday(local) + DAYS_IN_WEEK) % DAYS_IN_WEEK or DAYS_IN_WEEK
        next_week = any(tuple(words[max(0, index - len(w)) : index]) == w for w in NEXT_WEEK_WORDS)
        return offset + DAYS_IN_WEEK if next_week and offset < DAYS_IN_WEEK else offset
    next_week = "haftaya" in words
    fixed = next((offset for phrase, offset in _FIXED if phrase in folded_text), None)
    if fixed is not None:
        return fixed + DAYS_IN_WEEK if next_week else fixed
    return DAYS_IN_WEEK if next_week else None


def _date_offset(folded_text: str, today: date) -> int | None:
    """ "15 Kasım"."""
    found = _DATE.search(folded_text)
    if found is None:
        return None
    return offset_to_date(today, _MONTHS[found.group(2)], int(found.group(1)))


def offset_to_date(today: date, month: int, day: int) -> int | None:
    """Days to the next such date: this year's, or next year's once this year's has passed."""
    for year in (today.year, today.year + 1):
        try:
            target = date(year, month, day)
        except ValueError:
            return None
        if target >= today:
            return (target - today).days
    return None
