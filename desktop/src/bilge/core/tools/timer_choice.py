"""Which of the running timers a request means ("çay zamanlayıcısını iptal et", "ikincisini iptal et"), and how a
time left is said."""

from collections.abc import Sequence
from typing import Protocol

from bilge.core.text import folded

# Words that name the timer itself rather than what it is for ("çay zamanlayıcısı" is labelled "çay").
_GENERIC_PREFIXES = ("zamanlayici", "alarm", "timer", "hatirlatma", "reminder")
_SECONDS_SHOWN_UNDER = 10 * 60


class Labelled(Protocol):
    @property
    def label(self) -> str | None: ...


def chosen[T: Labelled](timers: Sequence[T], label: str | None, index: int | None) -> list[T]:
    """`timers` soonest first. The `index`-th (from 1), or those whose label matches `label`, or all of them when
    neither is given; empty when nothing matches."""
    if index is not None:
        return [timers[index - 1]] if 1 <= index <= len(timers) else []
    wanted = _significant(label)
    if not wanted:
        return list(timers)
    return [timer for timer in timers if timer.label and _matches(_significant(timer.label), wanted)]


def _significant(label: str | None) -> str:
    words = folded(label or "").split()
    return " ".join(word for word in words if not word.startswith(_GENERIC_PREFIXES))


def _matches(have: str, wanted: str) -> bool:
    # "çayın" is still the "çay" timer, and "çay demleme" the "çay" one.
    return bool(have) and (have in wanted or wanted in have)


def split_duration(seconds: int) -> tuple[int, int, int]:
    """(hours, minutes, seconds): seconds only matter in the last ten minutes; longer waits round to the minute."""
    seconds = max(0, seconds)
    if seconds >= _SECONDS_SHOWN_UNDER:
        minutes = (seconds + 30) // 60
        return minutes // 60, minutes % 60, 0
    return 0, seconds // 60, seconds % 60
