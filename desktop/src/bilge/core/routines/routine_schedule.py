"""A routine: a command Bilge runs on its own at a time of day on chosen days ("her gece 21'de hava durumunu
söyle"), when it is due, and how its schedule is said back."""

from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta
from enum import StrEnum

from bilge.core.language import AssistantLanguage
from bilge.core.text import time_locative

# Days are Python weekdays: 0 is Monday.
EVERY_DAY = frozenset(range(7))
WEEKDAYS = frozenset(range(5))
WEEKEND = frozenset({5, 6})
DAY_NAMES = {
    AssistantLanguage.TURKISH: ("pazartesi", "salı", "çarşamba", "perşembe", "cuma", "cumartesi", "pazar"),
    AssistantLanguage.ENGLISH: ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"),
}
_DAYS_AHEAD = 8


class PartOfDay(StrEnum):
    MORNING = "morning"
    NOON = "noon"
    EVENING = "evening"
    NIGHT = "night"


@dataclass(frozen=True)
class Routine:
    id: str
    days: frozenset[int]
    hour: int
    minute: int
    command: str


def latest_occurrence(routine: Routine, since: datetime, until: datetime) -> datetime | None:
    """The last time the routine was due in (since, until], or None."""
    day = until.replace(hour=routine.hour, minute=routine.minute, second=0, microsecond=0)
    while day > since:
        if day <= until and day.weekday() in routine.days:
            return day
        day -= timedelta(days=1)
    return None


def next_occurrence(routine: Routine, after: datetime) -> datetime | None:
    """The first time the routine is due after `after`; None for a routine with no days."""
    day = after.replace(hour=routine.hour, minute=routine.minute, second=0, microsecond=0)
    for _ in range(_DAYS_AHEAD):
        if day > after and day.weekday() in routine.days:
            return day
        day += timedelta(days=1)
    return None


def due(routines: Iterable[Routine], since: datetime, until: datetime, grace: timedelta) -> list[Routine]:
    """Those due in (since, until], each once; a time missed by more than `grace` (the computer was asleep, or
    Bilge was closed) is skipped rather than run late."""
    return [
        routine
        for routine in routines
        if (moment := latest_occurrence(routine, since, until)) is not None and until - moment <= grace
    ]


def part_of_day(hour: int) -> PartOfDay:
    if 5 <= hour < 12:
        return PartOfDay.MORNING
    if 12 <= hour < 17:
        return PartOfDay.NOON
    if 17 <= hour < 21:
        return PartOfDay.EVENING
    return PartOfDay.NIGHT


def sorted_routines(routines: Iterable[Routine]) -> list[Routine]:
    return sorted(routines, key=lambda r: (r.hour, r.minute, min(r.days, default=7), r.command))


def describe(days: frozenset[int], hour: int, minute: int, language: AssistantLanguage) -> str:
    """ "her gün 21:00'de", "hafta içi her gün 07:00'de", "pazartesi ve çarşamba 08:30'da";
    "every day at 21:00", "on weekdays at 07:00", "on Mondays and Wednesdays at 08:30"."""
    if language is AssistantLanguage.ENGLISH:
        return f"{_english_days(days)} at {hour:02d}:{minute:02d}"
    return f"{_turkish_days(days)} {time_locative(hour, minute)}"


def _turkish_days(days: frozenset[int]) -> str:
    if days == EVERY_DAY:
        return "her gün"
    if days == WEEKDAYS:
        return "hafta içi her gün"
    if days == WEEKEND:
        return "hafta sonları"
    names = [DAY_NAMES[AssistantLanguage.TURKISH][day] for day in sorted(days)]
    return "her " + names[0] if len(names) == 1 else _joined(names, "ve") + " günleri"


def _english_days(days: frozenset[int]) -> str:
    if days == EVERY_DAY:
        return "every day"
    if days == WEEKDAYS:
        return "on weekdays"
    if days == WEEKEND:
        return "on weekends"
    return "on " + _joined([DAY_NAMES[AssistantLanguage.ENGLISH][day] + "s" for day in sorted(days)], "and")


def _joined(names: Sequence[str], conjunction: str) -> str:
    if len(names) == 1:
        return names[0]
    return f"{', '.join(names[:-1])} {conjunction} {names[-1]}"
