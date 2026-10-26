"""Music asked for on a named service: "YouTube'da Tarkan aç", "YouTube Music'te Sezen Aksu çal", "Kuzu Kuzu'yu
Spotify'dan çal", "play Tarkan on Deezer". A service said as the object ("YouTube'u aç") or with nothing to play
is not such a request: it opens the app or the site."""

import re
from collections.abc import Callable
from dataclasses import dataclass
from enum import StrEnum

from bilge.core.text import folded


class MusicService(StrEnum):
    SPOTIFY = "spotify"
    YOUTUBE = "youtube"
    YOUTUBE_MUSIC = "youtube_music"
    DEEZER = "deezer"
    APPLE_MUSIC = "apple_music"


AUTO = "auto"
# The choices of the default service setting.
DEFAULT_CHOICES = (AUTO, *(service.value for service in MusicService))

NAMES = {
    MusicService.SPOTIFY: "Spotify",
    MusicService.YOUTUBE: "YouTube",
    MusicService.YOUTUBE_MUSIC: "YouTube Music",
    MusicService.DEEZER: "Deezer",
    MusicService.APPLE_MUSIC: "Apple Music",
}
# The names as said in Turkish with "-de": "yutub'da", "müzik'te".
LOCATIVES = {
    MusicService.SPOTIFY: "Spotify'da",
    MusicService.YOUTUBE: "YouTube'da",
    MusicService.YOUTUBE_MUSIC: "YouTube Music'te",
    MusicService.DEEZER: "Deezer'da",
    MusicService.APPLE_MUSIC: "Apple Music'te",
}


@dataclass(frozen=True)
class MusicRequest:
    query: str
    service: MusicService


# Folded words of each name; the last may carry a case ending ("youtubeda", "musicten"). Longer names first.
_SPOKEN_NAMES = (
    (MusicService.YOUTUBE_MUSIC, ("youtube", "music")),
    (MusicService.YOUTUBE_MUSIC, ("youtube", "muzik")),
    (MusicService.APPLE_MUSIC, ("apple", "music")),
    (MusicService.APPLE_MUSIC, ("apple", "muzik")),
    (MusicService.YOUTUBE, ("youtube",)),
    (MusicService.YOUTUBE, ("yutub",)),
    (MusicService.YOUTUBE, ("yutup",)),
    (MusicService.SPOTIFY, ("spotify",)),
    (MusicService.DEEZER, ("deezer",)),
)
# "-de" and "-den" in every vowel and consonant harmony; "-yu", "-ı" (the service as the object) are not here.
_PLACE_ENDINGS = frozenset({"", "da", "de", "ta", "te", "dan", "den", "tan", "ten"})
# Said apart from the name: "YouTube da", "Spotify üzerinden".
_PLACE_WORDS = frozenset({"da", "de", "ta", "te", "dan", "den", "tan", "ten", "uzerinden", "ustunden", "ile"})
_ENGLISH_PLACES = frozenset({"on", "in", "from", "via", "using", "with"})
_TURKISH_VERBS = frozenset({
    "ac", "cal", "oynat", "baslat", "dinlet", "dinle", "izle", "izlet", "koy", "acar", "calar", "oynatir", "koyar",
    "acsana", "calsana", "oynatsana", "koysana", "acabilir", "calabilir", "oynatabilir", "acin", "calin",
})  # fmt: skip
_ENGLISH_VERBS = (("put", "on"), ("listen", "to"), ("play",), ("start",), ("watch",), ("open",))
_LEADING = frozenset({"bilge", "hadi", "lutfen", "bana", "hey", "please", "can", "could", "you"})
_TRAILING = frozenset({"misin", "musun", "misiniz", "musunuz", "lutfen", "bakalim", "please", "now", "for", "me"})
# Around the name they say "music" rather than which: "Tarkan şarkıları" is Tarkan.
_MUSIC_WORDS = re.compile(r"(sarki|muzik|muzig|parca|album|song|music|track)\w*")
_LEADING_ARTICLES = frozenset({"bir", "biraz", "birkac", "some", "a", "by"})
# A request made only of such words names nothing to search for ("Spotify'da müzik çal", "YouTube'da bir video aç").
_NOTHING_NAMED = re.compile(
    r"(sarki|muzik|muzig|parca|album|song|music|track|video|something|anything)\w*|su|bu|this|that"
)


def parse(command: str) -> MusicRequest | None:
    said = _joined_you_tube([word for word in (part.strip('.,!?;:"“”') for part in command.split()) if word])
    words = [folded(word).replace(" ", "") for word in said]
    named = _service_at(words)
    if named is None:
        return None
    service, start, end = named
    if start > 0 and words[start - 1] in _ENGLISH_PLACES:
        start -= 1
    rest = _trimmed(said[:start] + said[end:])
    folded_rest = [folded(word) for word in rest]
    if folded_rest and folded_rest[-1] in _TURKISH_VERBS:
        rest = rest[:-1]
    else:
        opener = next((verb for verb in _ENGLISH_VERBS if tuple(folded_rest[: len(verb)]) == verb), None)
        if opener is None:
            return None
        rest = rest[len(opener) :]
    query = _query(rest)
    return MusicRequest(query, service) if query else None


def chosen_service(named: str | None, default: str, has_spotify: Callable[[], bool]) -> MusicService:
    """The service said, else the one set; "auto" is the Spotify app when it's installed, otherwise YouTube Music,
    which plays in any browser without an account."""
    for choice in (named, default):
        try:
            return MusicService(choice)
        except ValueError:
            continue
    return MusicService.SPOTIFY if has_spotify() else MusicService.YOUTUBE_MUSIC


def _service_at(words: list[str]) -> tuple[MusicService, int, int] | None:
    """The service and where its name (with a separate "da", "üzerinden") is in the words."""
    for index in range(len(words)):
        for service, stems in _SPOKEN_NAMES:
            last = index + len(stems) - 1
            if last >= len(words) or tuple(words[index:last]) != stems[:-1] or not words[last].startswith(stems[-1]):
                continue
            ending = words[last][len(stems[-1]) :]
            if ending not in _PLACE_ENDINGS:
                return None
            end = last + 1
            if not ending and end < len(words) and words[end] in _PLACE_WORDS:
                end += 1
            return service, index, end
    return None


def _joined_you_tube(said: list[str]) -> list[str]:
    """ "You Tube'da" as a recognizer may write it."""
    joined: list[str] = []
    for word in said:
        if joined and folded(joined[-1]) == "you" and folded(word).startswith("tube"):
            joined[-1] += word
        else:
            joined.append(word)
    return joined


def _trimmed(words: list[str]) -> list[str]:
    start, end = 0, len(words)
    while start < end and folded(words[start]) in _LEADING:
        start += 1
    while end > start and folded(words[end - 1]) in _TRAILING:
        end -= 1
    return words[start:end]


def _query(words: list[str]) -> str:
    """The words as said, each cut at its case ending ("Kuzu Kuzu'yu" → "Kuzu Kuzu", "Tarkan'ın şarkılarını" →
    "Tarkan"), without "bir", "şarkı", "müzik" around them."""
    cut = [word for word in (re.split(r"['’]", word)[0] for word in words) if word]
    if all(_NOTHING_NAMED.fullmatch(folded(word)) or folded(word) in _LEADING_ARTICLES for word in cut):
        return ""
    start, end = 0, len(cut)
    while start < end and (_MUSIC_WORDS.fullmatch(folded(cut[start])) or folded(cut[start]) in _LEADING_ARTICLES):
        start += 1
    while end > start and _MUSIC_WORDS.fullmatch(folded(cut[end - 1])):
        end -= 1
    return " ".join(cut[start:end])
