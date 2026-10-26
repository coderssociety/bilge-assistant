from collections.abc import Callable
from datetime import datetime, timedelta
from typing import Any

from bilge.brain.instructions import weekday_name
from bilge.core.language import AssistantLanguage
from bilge.core.text import locative
from bilge.core.tools import world_clock
from bilge.core.tools.world_clock import Place
from bilge.tools.base import Tool, ToolError

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "description": "Başka bir şehirde ya da ülkede saatin kaç olduğunu, ya da oranın buradan (veya iki yer arasında) kaç saat ileride/geride olduğunu söyler.",
        "place": "Şehir ya da ülke: 'Tokyo', 'New York', 'Almanya'",
        "other": "Fark iki yer arasında sorulduysa ikinci yer; yoksa boş bırak",
        "kind": "'time' saati, 'difference' saat farkını sorar",
        "unknown": "'{place}' için saat dilimini bilmiyorum.",
        "time": "{place_at} saat {clock}, {weekday}.",
        "ahead": "{place} bizden {gap} ileride; orada saat {clock}.",
        "behind": "{place} bizden {gap} geride; orada saat {clock}.",
        "same": "{place} ile aramızda saat farkı yok.",
        "ahead_of": "{place}, {other_from} {gap} ileride.",
        "behind_of": "{place}, {other_from} {gap} geride.",
        "same_as": "{place} ile {other} arasında saat farkı yok.",
        "hours": "{n} saat", "minutes": "{n} dakika",
    },
    AssistantLanguage.ENGLISH: {
        "description": "Tells the time in another city or country, or how many hours ahead or behind it is from here (or between two places).",
        "place": "A city or country: 'Tokyo', 'New York', 'Germany'",
        "other": "The second place when the difference between two places was asked; otherwise leave empty",
        "kind": "'time' for the time there, 'difference' for the time difference",
        "unknown": "I don't know the time zone of '{place}'.",
        "time": "It's {clock} on {weekday} in {place}.",
        "ahead": "{place} is {gap} ahead of you; it's {clock} there.",
        "behind": "{place} is {gap} behind you; it's {clock} there.",
        "same": "{place} is on the same time as you.",
        "ahead_of": "{place} is {gap} ahead of {other}.",
        "behind_of": "{place} is {gap} behind {other}.",
        "same_as": "{place} and {other} are on the same time.",
        "hours": "{n} hours", "hour": "1 hour", "minutes": "{n} minutes", "minute": "1 minute",
    },
}  # fmt: skip


def world_clock_tool(
    language: AssistantLanguage, clock: Callable[[], datetime] = lambda: datetime.now().astimezone()
) -> Tool:
    texts = _TEXTS[language]
    english = language is AssistantLanguage.ENGLISH

    def name(place: Place) -> str:
        return place.english if english else place.turkish

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        # A place in the table that was said wins over the model's reading of it.
        parsed = world_clock.parse(command)
        if parsed is None:
            return arguments
        other = parsed.places[1].english if len(parsed.places) > 1 else ""
        kind = "difference" if parsed.difference else "time"
        return {"place": parsed.places[0].english, "otherPlace": other, "kind": kind}

    def place_from(arguments: dict[str, Any], key: str) -> Place | None:
        given = str(arguments.get(key) or "").strip()
        if not given:
            return None
        place = world_clock.place_named(given)
        if place is None:
            raise ToolError(texts["unknown"].format(place=given))
        return place

    def run(arguments: dict[str, Any]) -> str:
        place = place_from(arguments, "place")
        if place is None:
            raise ToolError(texts["unknown"].format(place=""))
        other = place_from(arguments, "otherPlace")
        now = clock()
        there = world_clock.time_there(place, now)
        if arguments.get("kind") != "difference" and other is None:
            sentence = texts["time"].format(place=name(place), place_at=locative(name(place)), clock=f"{there:%H:%M}",
                                            weekday=weekday_name(there, language))  # fmt: skip
            return _capitalized(sentence)
        gap = world_clock.difference(place, now, other)
        if other is None:
            key = "same" if not gap else "ahead" if gap > timedelta() else "behind"
            return _capitalized(
                texts[key].format(place=name(place), gap=_spoken_gap(gap, texts), clock=f"{there:%H:%M}")
            )
        key = "same_as" if not gap else "ahead_of" if gap > timedelta() else "behind_of"
        sentence = texts[key].format(place=name(place), other=name(other), other_from=locative(name(other)) + "n",
                                     gap=_spoken_gap(gap, texts))  # fmt: skip
        return _capitalized(sentence)

    parameters = {
        "type": "object",
        "properties": {
            "place": {"type": "string", "description": texts["place"]},
            "otherPlace": {"type": "string", "description": texts["other"]},
            "kind": {"type": "string", "enum": ["time", "difference"], "description": texts["kind"]},
        },
        "required": ["place"],
    }
    return Tool("worldClock", texts["description"], run=run, parameters=parameters, refine=refine)


def _spoken_gap(gap: timedelta, texts: dict[str, str]) -> str:
    minutes = abs(int(gap.total_seconds())) // 60
    hours, rest = divmod(minutes, 60)
    parts = [_count(hours, "hour", texts) if hours else "", _count(rest, "minute", texts) if rest else ""]
    return " ".join(part for part in parts if part)


def _count(n: int, unit: str, texts: dict[str, str]) -> str:
    """ "1 hour" but "2 hours"; Turkish keeps the singular after a number."""
    return texts[unit] if n == 1 and unit in texts else texts[unit + "s"].format(n=n)


def _capitalized(sentence: str) -> str:
    return sentence[:1].upper() + sentence[1:]
