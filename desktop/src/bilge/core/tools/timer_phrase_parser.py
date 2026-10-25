"""Deterministically reads "20:00" or "1 saat 15 dakika" from a command that already went through
turkish_number_parser and turkish_time_of_day. Used to override the model's guesses for these values."""

import re
from dataclasses import dataclass

_MINUTES_PER_DAY = 24 * 60
_QUARTER_MINUTES = 15
_QUARTER_SECONDS = 900
_HALF_DAY_HOURS = 12


@dataclass(frozen=True)
class Result:
    hour: int | None
    minute: int | None
    duration_seconds: int | None
    # "sekize çeyrek kala" names no part of the day: it may be 07:45 or 19:45.
    either_half_day: bool = False


_CLOCK = re.compile(r"(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?!\d)")
# "8'e çeyrek kala", "09:00'u 20 geçe" (time_of_day already made "akşam sekize" a clock time).
_RELATIVE_CLOCK = re.compile(
    r"(?<![\d:])(?:([01]?\d|2[0-3]):([0-5]\d)|(\d{1,2}))(?:'?[^\W\d_]+)?\s+(çeyrek|\d{1,2})\s+(kala|geçe)(?![^\W\d_])",
    re.IGNORECASE,
)
# "bir" stays a word after digitizing, since it is also the article; before "buçuk" it can only be one.
_UNITS: tuple[tuple[re.Pattern[str], float], ...] = (
    (re.compile(r"(\d+|(?<![^\W\d_])bir)(\s+buçuk)?\s+saat", re.IGNORECASE), 3600),
    (re.compile(r"(\d+|(?<![^\W\d_])bir)(\s+buçuk)?\s+dakika", re.IGNORECASE), 60),
    (re.compile(r"(\d+|(?<![^\W\d_])bir)(\s+buçuk)?\s+saniye", re.IGNORECASE), 1),
)
# "üç çeyrek (saat)" is three quarters of an hour; it is read before the plain "çeyrek saat".
_QUARTERS = re.compile(r"(?<!\d)(\d+)\s+çeyrek(?:\s+saat)?(?![^\W\d_])", re.IGNORECASE)
_FRACTIONS_OF_HOUR: tuple[tuple[re.Pattern[str], float], ...] = (
    (re.compile(r"(?<![^\W\d_])yarım\s+saat", re.IGNORECASE), 1800),
    (re.compile(r"(?<![^\W\d_])çeyrek\s+saat", re.IGNORECASE), _QUARTER_SECONDS),
)


def parse(text: str) -> Result | None:
    relative = _relative_clock(text)
    if relative is not None:
        return relative
    clock = _CLOCK.search(text)
    if clock is not None:
        return Result(hour=int(clock.group(1)), minute=int(clock.group(2)), duration_seconds=None)
    total = 0.0
    for match in _QUARTERS.finditer(text):
        total += int(match.group(1)) * _QUARTER_SECONDS
    rest = _QUARTERS.sub(" ", text)
    for pattern, seconds in _UNITS:
        for match in pattern.finditer(rest):
            amount = 1.0 if match.group(1).isalpha() else float(match.group(1))
            half = 0.5 if match.group(2) is not None else 0
            total += (amount + half) * seconds
    for pattern, seconds in _FRACTIONS_OF_HOUR:
        if pattern.search(rest):
            total += seconds
    return Result(hour=None, minute=None, duration_seconds=int(total)) if total > 0 else None


def _relative_clock(text: str) -> Result | None:
    match = _RELATIVE_CLOCK.search(text)
    if match is None:
        return None
    bare_hour = match.group(3)
    hour = int(bare_hour if bare_hour is not None else match.group(1))
    if hour >= _HALF_DAY_HOURS * 2:
        return None
    base = hour * 60 + (int(match.group(2)) if bare_hour is None else 0)
    offset = _QUARTER_MINUTES if match.group(4).isalpha() else int(match.group(4))
    if not 0 < offset < 60:
        return None
    signed = -offset if match.group(5).lower() == "kala" else offset
    total = (base + signed) % _MINUTES_PER_DAY
    either = bare_hour is not None and 1 <= hour <= _HALF_DAY_HOURS
    return Result(hour=total // 60, minute=total % 60, duration_seconds=None, either_half_day=either)
