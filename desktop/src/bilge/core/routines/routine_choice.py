"""Which routines a spoken name means: "akşam rutini" (by the part of the day it runs in), "hava durumu rutini"
(by its command), or the n-th of the list."""

from collections.abc import Sequence

from bilge.core.routines.routine_schedule import PartOfDay, Routine, part_of_day
from bilge.core.text import folded
from bilge.core.tools import phrase_matcher

_PARTS = {
    "sabah": PartOfDay.MORNING, "sabahki": PartOfDay.MORNING, "morning": PartOfDay.MORNING,
    "ogle": PartOfDay.NOON, "oglen": PartOfDay.NOON, "ogleden": PartOfDay.NOON, "ogleki": PartOfDay.NOON,
    "noon": PartOfDay.NOON, "afternoon": PartOfDay.NOON,
    "aksam": PartOfDay.EVENING, "aksamki": PartOfDay.EVENING, "evening": PartOfDay.EVENING,
    "gece": PartOfDay.NIGHT, "geceki": PartOfDay.NIGHT, "night": PartOfDay.NIGHT,
}  # fmt: skip


def chosen(routines: Sequence[Routine], name: str | None, index: int | None = None) -> list[Routine]:
    """`routines` in the order they are listed. The `index`-th (from 1), those the name fits, or all of them when
    neither is given; empty when nothing fits."""
    if index is not None:
        return [routines[index - 1]] if 1 <= index <= len(routines) else []
    words = folded(name or "").split()
    parts = {_PARTS[word] for word in words if word in _PARTS}
    rest = " ".join(word for word in words if word not in _PARTS and word != "sonra")
    picked = [routine for routine in routines if not parts or part_of_day(routine.hour) in parts]
    if not rest:
        return picked
    return [
        routine for routine in picked if phrase_matcher.score(rest, routine.command) >= phrase_matcher.MINIMUM_SCORE
    ]
