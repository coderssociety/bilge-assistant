"""Turkish radio stations by the names people say ("Power FM", "TRT FM"), and the stream to play for one from
radio-browser.info's station list."""

from dataclasses import dataclass
from typing import Any
from urllib.parse import urlencode, urlsplit

from bilge.core.text import folded
from bilge.core.web import spoken_names

# The accusative and genitive a station name takes when asked for: "Power FM'i aç", "Virgin Radio'yu aç".
STATION_ENDINGS = spoken_names.ENDINGS | frozenset({"i", "yi", "u", "yu", "ni", "nu"})
# Codecs every PyAV build decodes; anything else is tried only when nothing better is listed.
_KNOWN_CODECS = frozenset({"MP3", "AAC", "AAC+", "OGG", "OPUS"})


@dataclass(frozen=True)
class Station:
    name: str
    # What radio-browser's name search is asked for.
    search: str
    aliases: tuple[str, ...] = ()


STATIONS = (
    Station("TRT FM", "TRT FM"),
    Station("TRT Radyo 1", "TRT Radyo 1", ("TRT Radyo Bir", "Radyo 1", "Radyo Bir")),
    Station("TRT Türkü", "TRT Türkü"),
    Station("TRT Nağme", "TRT Nağme"),
    Station("Power FM", "Power FM", ("Pawer FM",)),
    Station("Power Türk", "Power Türk", ("PowerTürk",)),
    Station("Power Pop", "Power Pop"),
    Station("Kral FM", "Kral FM"),
    Station("Kral Pop", "Kral Pop"),
    Station("Süper FM", "Süper FM", ("Super FM",)),
    Station("Joy FM", "Joy FM"),
    Station("Joy Türk", "Joy Türk", ("JoyTürk",)),
    Station("Metro FM", "Metro FM"),
    Station("Virgin Radio", "Virgin Radio", ("Virgin Radyo",)),
    Station("Best FM", "Best FM"),
    Station("Radyo Fenomen", "Radyo Fenomen", ("Fenomen",)),
    Station("Pal Station", "Pal Station"),
    Station("Show Radyo", "Show Radyo"),
    Station("Radyo D", "Radyo D"),
    Station("Radyo Viva", "Radyo Viva"),
    Station("Radyo 7", "Radyo 7", ("Radyo Yedi",)),
    Station("Radyo Eksen", "Radyo Eksen", ("Eksen",)),
    Station("Alem FM", "Alem FM"),
    Station("Radyo Trafik", "Radyo Trafik"),
)
DEFAULT = STATIONS[0]


def mentioned(command: str) -> Station | None:
    names = [(spelling, station) for station in STATIONS for spelling in (station.name, *station.aliases)]
    return spoken_names.find(command, names, STATION_ENDINGS)


def search_query(term: str, country: str | None = "TR") -> str:
    """The query string for radio-browser's station search, the most voted first."""
    fields = {"name": term, "hidebroken": "true", "order": "votes", "reverse": "true", "limit": "30"}
    return urlencode({**fields, **({"countrycode": country} if country else {})})


@dataclass(frozen=True)
class Stream:
    url: str
    # A playlist of segments (HLS) rather than one continuous stream.
    is_playlist: bool


def ranked(results: Any, wanted: str) -> list[Stream]:
    """The streams for the name asked, best first: the closest name, then a plain stream over a playlist, https
    over http, a codec every build decodes, and then the most votes. Only the closest names are kept, so a
    failing stream gives way to another of the same station, not to a different one. Entries that don't read are
    skipped."""
    entries = results if isinstance(results, list) else []
    found = [candidate for entry in entries if (candidate := _candidate(entry, folded(wanted))) is not None]
    if not found:
        return []
    found.sort(key=lambda candidate: candidate[0], reverse=True)
    closest = found[0][0][0]
    return list(dict.fromkeys(stream for score, stream in found if score[0] == closest))


def choose(results: Any, wanted: str) -> Stream | None:
    streams = ranked(results, wanted)
    return streams[0] if streams else None


def _candidate(entry: Any, wanted: str) -> tuple[tuple, Stream] | None:
    if not isinstance(entry, dict) or entry.get("lastcheckok", 1) != 1:
        return None
    url = str(entry.get("url_resolved") or entry.get("url") or "").strip()
    try:
        scheme = urlsplit(url).scheme
    except ValueError:
        return None
    if scheme not in ("http", "https"):
        return None
    name = folded(str(entry.get("name") or ""))
    playlist = entry.get("hls") == 1 or ".m3u8" in url.lower()
    votes = entry.get("votes") if isinstance(entry.get("votes"), int) else 0
    score = (
        _closeness(name, wanted),
        not playlist,
        url.startswith("https://"),
        str(entry.get("codec") or "").upper() in _KNOWN_CODECS or playlist,
        votes,
    )
    return score, Stream(url, playlist)


def _closeness(name: str, wanted: str) -> int:
    if name == wanted:
        return 3
    if name.startswith(wanted):
        return 2
    return 1 if all(word in name.split() for word in wanted.split()) else 0
