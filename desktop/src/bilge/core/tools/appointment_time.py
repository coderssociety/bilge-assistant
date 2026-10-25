"""The clock time of a Turkish appointment or reminder, read from a command that already went through
turkish_number_parser and turkish_time_of_day ("saat 2'de", "9 buçukta", "20:00'de"), and how far ahead
"yarım saat sonra" is. A bare 1 to 6 means the afternoon: nobody books the dentist for two at night."""

import re

from bilge.core.text import folded
from bilge.core.tools import timer_phrase_parser

_LAST_AFTERNOON_HOUR = 6
_CLOCK = re.compile(r"(?<![\d:])(\d{1,2}):([0-5]\d)(?!\d)")
_SAID_HOUR = re.compile(
    r"(?<![^\W\d_])saat\s+(\d{1,2})(?![\d:])(?:'[^\W\d_]+)?(\s+buçuk)?"
    r"|(?<![\d:'])(\d{1,2})\s+buçuk(?![^\W\d_]*\s+(?:saat|dakika))"
    r"|(?<![\d:'])(\d{1,2})'[dt][ae](?![^\W\d_])",
    re.IGNORECASE,
)
# "akşamları 8'de", "geceleri 11'de": a routine's plural day parts shift the hour as the singular ones do.
_MORNING = frozenset({"sabah", "sabahlari", "sabahleyin", "sabahki"})
_EVENING = frozenset({"aksam", "aksamlari", "aksamleyin", "aksamki"})
_NIGHT = frozenset({"gece", "geceleri", "geceleyin", "geceki"})
_FROM_NOW = re.compile(r"(?:saat|dakika|saniye)[^\W\d_]*\s+sonra", re.IGNORECASE)


def clock(text: str) -> tuple[int, int] | None:
    """(hour, minute) on a 24-hour clock, or None when no time of day is said."""
    found = _CLOCK.search(text)
    if found is not None:
        hour, minute = int(found.group(1)), int(found.group(2))
        # turkish_time_of_day writes "02:00" for "sabah 2"; a recognizer's own "2:00" is as bare as "saat 2".
        bare = len(found.group(1)) == 1
        return (_afternoon(hour, folded(text)) if bare else hour), minute
    said = _SAID_HOUR.search(text)
    if said is None:
        return None
    hour = int(said.group(1) or said.group(3) or said.group(4))
    half = said.group(2) is not None or said.group(3) is not None
    if hour > 23:
        return None
    return _afternoon(hour, folded(text)), 30 if half else 0


def seconds_from_now(text: str) -> int | None:
    """ "yarım saat sonra" → 1800, "2 saat sonra" → 7200; None when no duration ahead is said."""
    if _FROM_NOW.search(text) is None:
        return None
    parsed = timer_phrase_parser.parse(text)
    return parsed.duration_seconds if parsed is not None else None


def _afternoon(hour: int, folded_text: str) -> int:
    words = set(folded_text.split())
    if words & _MORNING or hour >= 12:
        return hour
    if words & _EVENING or ("ogleden" in words and "sonra" in words):
        return hour + 12
    if words & _NIGHT:
        return hour + 12 if hour > _LAST_AFTERNOON_HOUR else hour
    return hour + 12 if 1 <= hour <= _LAST_AFTERNOON_HOUR else hour
