"""Prayer times: what a question asks ("akşam ezanı kaçta", "iftara ne kadar var", "bugünkü namaz vakitleri"), the
times read from Diyanet's monthly table (ezanvakti.emushaf.net) or Aladhan's Diyanet method, and the spoken answer."""

import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from enum import StrEnum
from typing import Any

from bilge.core import text


class Vakit(StrEnum):
    IMSAK = "imsak"
    GUNES = "gunes"
    OGLE = "ogle"
    IKINDI = "ikindi"
    AKSAM = "aksam"
    YATSI = "yatsi"


class Occasion(StrEnum):
    IFTAR = "iftar"
    SAHUR = "sahur"


@dataclass(frozen=True)
class DayTimes:
    day: date
    times: dict[Vakit, time]


@dataclass(frozen=True)
class Question:
    vakit: Vakit | None = None
    occasion: Occasion | None = None
    day_offset: int = 0
    whole_day: bool = False
    remaining: bool = False


# Folded word stems, the most specific first: "sabah ezanı" is read at imsak in Diyanet's table.
_TURKISH_VAKITS = (
    ("imsak", Vakit.IMSAK, None), ("sahur", Vakit.IMSAK, Occasion.SAHUR), ("iftar", Vakit.AKSAM, Occasion.IFTAR),
    ("ogle", Vakit.OGLE, None), ("ikindi", Vakit.IKINDI, None), ("aksam", Vakit.AKSAM, None),
    ("yatsi", Vakit.YATSI, None), ("gunes", Vakit.GUNES, None), ("sabah", Vakit.IMSAK, None),
)  # fmt: skip
_ENGLISH_VAKITS = {
    "imsak": (Vakit.IMSAK, None), "fajr": (Vakit.IMSAK, None), "dawn": (Vakit.IMSAK, None),
    "suhoor": (Vakit.IMSAK, Occasion.SAHUR), "sahur": (Vakit.IMSAK, Occasion.SAHUR),
    "sehri": (Vakit.IMSAK, Occasion.SAHUR), "sunrise": (Vakit.GUNES, None), "dhuhr": (Vakit.OGLE, None),
    "zuhr": (Vakit.OGLE, None), "noon": (Vakit.OGLE, None), "midday": (Vakit.OGLE, None), "asr": (Vakit.IKINDI, None),
    "afternoon": (Vakit.IKINDI, None), "maghrib": (Vakit.AKSAM, None), "iftar": (Vakit.AKSAM, Occasion.IFTAR),
    "sunset": (Vakit.AKSAM, None), "evening": (Vakit.AKSAM, None), "isha": (Vakit.YATSI, None),
    "night": (Vakit.YATSI, None),
}  # fmt: skip
_TURKISH_TIME_QUESTIONS = ("kacta", "ne zaman", "saat kac", "ne kadar", "kac dakika", "kac saat", "kaldi", "kalan",
                           "vakit", "vakt", "saatleri", "okunacak", "okunuyor")  # fmt: skip
_TURKISH_REMAINING = ("ne kadar var", "ne kadar kaldi", "kac dakika", "kac saat", "kaldi", "kalan", "kalmis")
# "Ezan nedir", "ezanı kim okuyor": about the call itself, not its time.
_TURKISH_NOT_A_TIME = ("nedir", "ne demek", "anlami", "nasil", "kim", "kimdir", "neden")
_ENGLISH_PRAYER = ("prayer", "adhan", "azan", "athan", "salah", "namaz", "fajr", "dhuhr", "zuhr", "asr", "maghrib",
                   "isha", "iftar", "suhoor", "sahur", "imsak")  # fmt: skip
_ENGLISH_TIME_QUESTIONS = ("when", "time", "times", "long", "until", "till", "left", "schedule", "timetable")
_ENGLISH_REMAINING = ("how long", "how much time", "how many minutes", "how many hours", "until", "till", "left",
                      "remaining")  # fmt: skip


def _has(phrases: tuple[str, ...], folded: str) -> bool:
    padded = f" {folded} "
    return any(f" {phrase}" in padded for phrase in phrases)


def claims(command: str, english: bool) -> bool:
    """A question about a prayer time, sure enough to answer without the model."""
    folded = text.folded(command)
    words = folded.split()
    if english:
        return any(w.startswith(_ENGLISH_PRAYER) for w in words) and any(w in _ENGLISH_TIME_QUESTIONS for w in words)
    if any(w in _TURKISH_NOT_A_TIME for w in words) or "ne demek" in folded:
        return False
    if any(w.startswith("ezan") for w in words):
        return True
    timed = _has(_TURKISH_TIME_QUESTIONS, folded)
    named = any(w.startswith(("imsak", "sahur", "iftar", "namaz", "ikindi", "yatsi")) for w in words)
    return timed and named


def question(command: str, english: bool, day_offset: int | None = None) -> Question:
    folded = text.folded(command)
    words = folded.split()
    vakit, occasion = _vakit(words, english)
    if english:
        whole = vakit is None and ("times" in words or "timetable" in words or "schedule" in words)
        remaining = _has(_ENGLISH_REMAINING, folded)
    else:
        whole = vakit is None and any(w.startswith(("vakitler", "saatleri", "imsakiye")) for w in words)
        remaining = _has(_TURKISH_REMAINING, folded)
    return Question(vakit, occasion, day_offset or 0, whole, remaining)


def _vakit(words: list[str], english: bool) -> tuple[Vakit | None, Occasion | None]:
    if english:
        return next((_ENGLISH_VAKITS[w] for w in words if w in _ENGLISH_VAKITS), (None, None))
    for stem, vakit, occasion in _TURKISH_VAKITS:
        # "Öğleden sonra" is not öğle; "güneşli" is the weather.
        if any(w.startswith(stem) and not w.startswith(("ogleden", "gunesli")) for w in words):
            return vakit, occasion
    return None, None


_EZANVAKTI_KEYS = {Vakit.IMSAK: "Imsak", Vakit.GUNES: "Gunes", Vakit.OGLE: "Ogle", Vakit.IKINDI: "Ikindi",
                   Vakit.AKSAM: "Aksam", Vakit.YATSI: "Yatsi"}  # fmt: skip
_ALADHAN_KEYS = {Vakit.IMSAK: "Fajr", Vakit.GUNES: "Sunrise", Vakit.OGLE: "Dhuhr", Vakit.IKINDI: "Asr",
                 Vakit.AKSAM: "Maghrib", Vakit.YATSI: "Isha"}  # fmt: skip
_CLOCK = re.compile(r"(\d{1,2}):(\d{2})")


def _time(value: Any) -> time | None:
    found = _CLOCK.match(str(value or "").strip())
    if found is None:
        return None
    hour, minute = int(found.group(1)), int(found.group(2))
    return time(hour, minute) if hour < 24 and minute < 60 else None


def _times(entry: dict[str, Any], keys: dict[Vakit, str]) -> dict[Vakit, time] | None:
    times = {vakit: _time(entry.get(key)) for vakit, key in keys.items()}
    if any(value is None for value in times.values()):
        return None
    return {vakit: value for vakit, value in times.items() if value is not None}


def _day(value: Any, pattern: str) -> date | None:
    try:
        return datetime.strptime(str(value), pattern).date()
    except ValueError:
        return None


def from_ezanvakti(data: Any) -> dict[date, DayTimes]:
    """The month list from /vakitler/{ilçe}: one entry per day, dated "20.10.2026"."""
    days: dict[date, DayTimes] = {}
    for entry in data if isinstance(data, list) else []:
        if not isinstance(entry, dict):
            continue
        day = _day(entry.get("MiladiTarihKisa"), "%d.%m.%Y")
        times = _times(entry, _EZANVAKTI_KEYS)
        if day is not None and times is not None:
            days[day] = DayTimes(day, times)
    return days


def from_aladhan(data: Any) -> DayTimes | None:
    """One day from /v1/timingsByCity; with the Diyanet method Fajr is Diyanet's imsak."""
    if not isinstance(data, dict) or data.get("code") != 200 or not isinstance(data.get("data"), dict):
        return None
    timings = data["data"].get("timings")
    gregorian = (data["data"].get("date") or {}).get("gregorian") or {}
    day = _day(gregorian.get("date"), "%d-%m-%Y")
    times = _times(timings, _ALADHAN_KEYS) if isinstance(timings, dict) else None
    return DayTimes(day, times) if day is not None and times is not None else None


def province_id(cities: Any, province: str) -> str | None:
    """The SehirID of a province in /sehirler/2 (Turkey)."""
    wanted = text.folded(province)
    for city in cities if isinstance(cities, list) else []:
        if isinstance(city, dict) and text.folded(str(city.get("SehirAdi") or "")) == wanted:
            return str(city.get("SehirID") or "") or None
    return None


def centre_id(districts: Any, province: str) -> str | None:
    """The IlceID of the province's centre in /ilceler/{SehirID}: every province lists it under its own name."""
    wanted = text.folded(province)
    for district in districts if isinstance(districts, list) else []:
        if isinstance(district, dict) and text.folded(str(district.get("IlceAdi") or "")) == wanted:
            return str(district.get("IlceID") or "") or None
    return None


def at(days: dict[date, DayTimes], day: date, vakit: Vakit, now: datetime) -> datetime | None:
    found = days.get(day)
    return datetime.combine(day, found.times[vakit], now.tzinfo) if found else None


def upcoming(days: dict[date, DayTimes], now: datetime) -> tuple[Vakit, datetime] | None:
    """The next vakit after `now`, tomorrow's imsak after the night prayer."""
    for offset in (0, 1):
        day = now.date() + timedelta(days=offset)
        for vakit in Vakit:
            moment = at(days, day, vakit, now)
            if moment is not None and moment > now:
                return vakit, moment
    return None
