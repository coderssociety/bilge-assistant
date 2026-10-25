"""What an earthquake question asks for ("İzmir'de deprem var mı", "bugün büyük deprem oldu mu", "en son deprem
nerede"), which of the listed earthquakes answer it, and the spoken answer."""

import re
from dataclasses import dataclass
from datetime import datetime, timedelta

from bilge.core import text
from bilge.core.language import AssistantLanguage
from bilge.core.web import provinces
from bilge.core.web.earthquake_feed import Earthquake

RECENT_HOURS = 24
# Smaller ones go unfelt and would crowd the list.
LISTED_MAGNITUDE = 2.0
BIG_MAGNITUDE = 4.0
NEAR_KM = 100
LISTED_COUNT = 5

# Whole words of the folded command: "büyüklüğü kaç" asks for a magnitude, not for big ones only.
_BIG = re.compile(r"\b(buyuk|siddetli|korkutucu|big|major|strong|large)\b")
_TODAY = re.compile(r"\b(bugun|bugunku|todays?)\b")
_LATEST = re.compile(r"\b(en son|son deprem\w*|latest|most recent|last earthquake)\b")
_PLURAL = re.compile(r"\b(depremler\w*|earthquakes)\b")


@dataclass(frozen=True)
class Query:
    # A province ("İzmir"), or any other place name to look for in the list ("Sındırgı").
    province: provinces.Place | None = None
    place: str = ""
    today: bool = False
    big: bool = False
    latest: bool = False

    @property
    def minimum(self) -> float:
        return BIG_MAGNITUDE if self.big else LISTED_MAGNITUDE


def read(command: str, place: str = "") -> Query:
    """The question as said; `place` is the model's reading, kept only when the command names it."""
    lowered = text.folded(command)
    province = provinces.mentioned(command)
    said = place.strip()
    if said and not any(word.startswith(text.folded(said)[:4]) for word in text.folded(command).split()):
        said = ""
    if province is None and said:
        province = provinces.named(said)
    return Query(
        province=province,
        place="" if province else said,
        today=_TODAY.search(lowered) is not None,
        big=_BIG.search(lowered) is not None,
        latest=_LATEST.search(lowered) is not None and _PLURAL.search(lowered) is None,
    )


def select(quakes: list[Earthquake], query: Query, now: datetime) -> list[Earthquake]:
    """Newest first. `now` carries the user's time zone, which decides where "today" starts."""
    since = (
        now.replace(hour=0, minute=0, second=0, microsecond=0) if query.today else now - timedelta(hours=RECENT_HOURS)
    )
    chosen = [q for q in quakes if q.time >= since and q.magnitude >= query.minimum]
    if query.province is not None:
        chosen = [q for q in chosen if q.distance_km(query.province) <= NEAR_KM]
    elif query.place:
        wanted = text.folded(query.place)
        chosen = [q for q in chosen if wanted in text.folded(q.place)]
    return sorted(chosen, key=lambda q: q.time, reverse=True)


def answer(
    chosen: list[Earthquake],
    query: Query,
    now: datetime,
    language: AssistantLanguage,
    home: provinces.Place | None = None,
    source: str = "AFAD",
) -> str:
    english = language is AssistantLanguage.ENGLISH
    reference = query.province or home
    if not chosen:
        body = _nothing(query, english)
    elif query.latest:
        latest = describe(chosen[0], now, language, reference)
        body = f"The latest earthquake: {latest}." if english else f"En son deprem: {latest}."
    else:
        listed = "; ".join(describe(q, now, language, reference) for q in chosen[:LISTED_COUNT])
        body = _summary(len(chosen), query, english) + listed + "."
    return f"{body} {'Source' if english else 'Kaynak'}: {source}."


def describe(
    quake: Earthquake, now: datetime, language: AssistantLanguage, reference: provinces.Place | None = None
) -> str:
    """ "Sındırgı, Balıkesir: büyüklük 4,6, 3 dakika önce, derinlik 10 km, İstanbul'dan 140 km uzakta"."""
    english = language is AssistantLanguage.ENGLISH
    magnitude = f"{quake.magnitude:.1f}" if english else f"{quake.magnitude:.1f}".replace(".", ",")
    depth = max(1, round(quake.depth_km))
    parts = [
        f"magnitude {magnitude}" if english else f"büyüklük {magnitude}",
        time_ago(now - quake.time, language),
        f"{depth} km deep" if english else f"derinlik {depth} km",
    ]
    if reference is not None:
        distance = round(quake.distance_km(reference))
        parts.append(
            f"{distance} km from {reference.name}"
            if english
            else f"{text.locative(reference.name)}n {distance} km uzakta"
        )
    return f"{quake.place}: {', '.join(parts)}"


def time_ago(elapsed: timedelta, language: AssistantLanguage) -> str:
    english = language is AssistantLanguage.ENGLISH
    minutes = max(0, int(elapsed.total_seconds() // 60))
    if minutes < 1:
        return "just now" if english else "az önce"
    if minutes < 60:
        return _ago(minutes, "minute", "dakika", english)
    if minutes < 24 * 60:
        return _ago(minutes // 60, "hour", "saat", english)
    return _ago(minutes // (24 * 60), "day", "gün", english)


def _ago(count: int, unit: str, birim: str, english: bool) -> str:
    if english:
        return f"{count} {unit}{'' if count == 1 else 's'} ago"
    return f"{count} {birim} önce"


def _scope(query: Query, english: bool) -> tuple[str, str]:
    """When and where, as the two languages put them."""
    near = query.province.name if query.province else query.place
    if english:
        return ("today" if query.today else f"in the last {RECENT_HOURS} hours"), (f" near {near}" if near else "")
    when = "Bugün" if query.today else f"Son {RECENT_HOURS} saatte"
    return when, (f" {near} yakınında" if near else "")


def _magnitude_words(query: Query, english: bool) -> str:
    minimum = f"{query.minimum:g}"
    return f"of magnitude {minimum} or more" if english else f"{minimum} ve üzeri büyüklükte"


def _summary(count: int, query: Query, english: bool) -> str:
    when, near = _scope(query, english)
    more = count > LISTED_COUNT
    if english:
        noun = "earthquake" if count == 1 else "earthquakes"
        return f"{count} {noun} {_magnitude_words(query, english)}{near} {when}" + (", the latest: " if more else ": ")
    return f"{when}{near} {_magnitude_words(query, english)} {count} deprem kaydedildi" + (
        ", en yenileri: " if more else ": "
    )


def _nothing(query: Query, english: bool) -> str:
    when, near = _scope(query, english)
    if english:
        return f"No earthquakes {_magnitude_words(query, english)}{near} {when}."
    return f"{when}{near} {_magnitude_words(query, english)} deprem kaydedilmedi."
