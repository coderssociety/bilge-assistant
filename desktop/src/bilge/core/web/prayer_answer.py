"""The spoken answer to a prayer-time question: the vakit asked, or the next one, with the time left until it."""

import math
from datetime import date, datetime, timedelta

from bilge.core import text
from bilge.core.language import AssistantLanguage
from bilge.core.web.prayer_times import DayTimes, Occasion, Question, Vakit, at, upcoming

_TURKISH_NAMES = {
    Vakit.IMSAK: "imsak", Vakit.GUNES: "güneş", Vakit.OGLE: "öğle ezanı", Vakit.IKINDI: "ikindi ezanı",
    Vakit.AKSAM: "akşam ezanı", Vakit.YATSI: "yatsı ezanı",
}  # fmt: skip
_TURKISH_SHORT = {Vakit.IMSAK: "imsak", Vakit.GUNES: "güneş", Vakit.OGLE: "öğle", Vakit.IKINDI: "ikindi",
                  Vakit.AKSAM: "akşam", Vakit.YATSI: "yatsı"}  # fmt: skip
_ENGLISH_NAMES = {Vakit.IMSAK: "fajr (imsak)", Vakit.GUNES: "sunrise", Vakit.OGLE: "dhuhr", Vakit.IKINDI: "asr",
                  Vakit.AKSAM: "maghrib", Vakit.YATSI: "isha"}  # fmt: skip
_ENGLISH_SHORT = {**_ENGLISH_NAMES, Vakit.IMSAK: "fajr"}


def answer(
    days: dict[date, DayTimes], now: datetime, city: str, asked: Question, day_name: str, language: AssistantLanguage
) -> str | None:
    """`day_name` names the asked day ("yarın", "tomorrow"); None when the needed days are missing."""
    english = language is AssistantLanguage.ENGLISH
    day = now.date() + timedelta(days=asked.day_offset)
    if asked.whole_day:
        return _whole_day(days.get(day), city, day_name, english)
    if asked.vakit is None:
        found = upcoming(days, now)
        if found is None:
            return None
        vakit, moment = found
        return _next(city, vakit, moment, now, english)
    moment = at(days, day, asked.vakit, now)
    if moment is None:
        return None
    name = _name(asked.vakit, asked.occasion, english)
    if asked.day_offset > 0:
        return _on_day(city, name, moment, day_name, english, now if asked.remaining else None)
    if moment > now:
        return _today(city, name, moment, now, english)
    tomorrow = at(days, day + timedelta(days=1), asked.vakit, now)
    return _passed(city, name, moment, tomorrow, now if asked.remaining else None, english)


def remaining(until: datetime, now: datetime, english: bool) -> str:
    """ "1 saat 12 dakika", "12 minutes": whole minutes, rounded up so a start in 30 seconds is not "0"."""
    minutes = max(1, math.ceil((until - now).total_seconds() / 60))
    hours, minutes = divmod(minutes, 60)
    if english:
        parts = [f"{hours} hour{'s' if hours != 1 else ''}"] if hours else []
        parts += [f"{minutes} minute{'s' if minutes != 1 else ''}"] if minutes else []
        return " ".join(parts)
    parts = ([f"{hours} saat"] if hours else []) + ([f"{minutes} dakika"] if minutes else [])
    return " ".join(parts)


def _name(vakit: Vakit, occasion: Occasion | None, english: bool) -> str:
    if occasion is Occasion.IFTAR:
        return "iftar"
    return (_ENGLISH_NAMES if english else _TURKISH_NAMES)[vakit]


def _clock(moment: datetime) -> str:
    return f"{moment:%H:%M}"


def _locative_clock(moment: datetime) -> str:
    return text.time_locative(moment.hour, moment.minute)


def _today(city: str, name: str, moment: datetime, now: datetime, english: bool) -> str:
    left = remaining(moment, now, english)
    if english:
        return f"In {city}, {name} is at {_clock(moment)}, in {left}."
    return f"{text.locative(city)} {name} {_locative_clock(moment)}; {left} var."


def _next(city: str, vakit: Vakit, moment: datetime, now: datetime, english: bool) -> str:
    left = remaining(moment, now, english)
    tomorrow = moment.date() > now.date()
    if english:
        when = "tomorrow at" if tomorrow else "at"
        return f"The next prayer time in {city} is {_ENGLISH_NAMES[vakit]}, {when} {_clock(moment)}, in {left}."
    when = "yarın " if tomorrow else ""
    return f"{text.locative(city)} sıradaki vakit {_TURKISH_NAMES[vakit]}: {when}{_locative_clock(moment)}; {left} var."


def _on_day(city: str, name: str, moment: datetime, day_name: str, english: bool, now: datetime | None) -> str:
    if english:
        left = f", in {remaining(moment, now, english)}" if now is not None else ""
        return f"In {city} {day_name}, {name} is at {_clock(moment)}{left}."
    left = f"; {remaining(moment, now, english)} var" if now is not None else ""
    return f"{text.locative(city)} {day_name} {name} {_locative_clock(moment)}{left}."


def _passed(
    city: str, name: str, moment: datetime, tomorrow: datetime | None, now: datetime | None, english: bool
) -> str:
    if english:
        said = f"In {city}, today's {name} was at {_clock(moment)}"
        if tomorrow is None:
            return said + "."
        left = f", in {remaining(tomorrow, now, english)}" if now is not None else ""
        return f"{said}; tomorrow it is at {_clock(tomorrow)}{left}."
    located = _locative_clock(moment)
    # The past of "18:03'te" is "18:03'teydi", of "18:30'da" "18:30'daydı".
    said = f"{text.locative(city)} bugünkü {name} {located}{'ydı' if located.endswith('a') else 'ydi'}"
    if tomorrow is None:
        return said + "."
    left = f"; {remaining(tomorrow, now, english)} var" if now is not None else ""
    return f"{said}; yarın {_locative_clock(tomorrow)}{left}."


def _whole_day(found: DayTimes | None, city: str, day_name: str, english: bool) -> str | None:
    if found is None:
        return None
    names = _ENGLISH_SHORT if english else _TURKISH_SHORT
    listed = ", ".join(f"{names[vakit]} {found.times[vakit]:%H:%M}" for vakit in Vakit)
    if english:
        return f"Prayer times in {city} {day_name}: {listed}."
    return f"{text.locative(city)} {day_name} namaz vakitleri: {listed}."
