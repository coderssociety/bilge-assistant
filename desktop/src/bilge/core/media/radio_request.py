"""Radio commands said in Turkish or English: "radyo aç", "Power FM'i çal", "radyoyu kapat", "radyonun sesini kıs",
"hangi radyo çalıyor"; "play the radio", "turn the radio down", "which station is this"."""

import re
from dataclasses import dataclass
from enum import StrEnum

from bilge.core.media import radio_stations
from bilge.core.text import folded


class RadioAction(StrEnum):
    PLAY = "play"
    STOP = "stop"
    QUIETER = "quieter"
    LOUDER = "louder"
    NOW_PLAYING = "nowPlaying"


@dataclass(frozen=True)
class RadioRequest:
    action: RadioAction
    # A listed station's name, the name as said for any other, or None for the last one played.
    station: str | None = None


_FILLERS = frozenset({"bilge", "lutfen", "misin", "musun", "bakalim", "hadi", "biraz", "please", "the", "a", "now"})
_PLAY = frozenset({"ac", "cal", "baslat", "dinle", "dinlet", "acar", "calar", "acsana", "calsana", "play"})
_STOP = frozenset({"kapat", "durdur", "kes", "sustur", "kapatir", "durdurur", "kapatsana", "off", "stop"})
_QUIETER = frozenset({"kis", "kisar", "azalt", "azaltir", "alcalt", "dusur", "down", "quieter", "lower"})
_LOUDER = frozenset({"artir", "artirir", "yukselt", "yukseltir", "ac", "acar", "up", "louder"})
_ENGLISH_PLAY = (("turn", "on"), ("put", "on"), ("play",), ("start",), ("listen", "to"))
_WHICH = re.compile(r"\b(hangi (radyo|istasyon)\w*|radyo\w* hangisi|(which|what) (radio|station))\b")


def parse(command: str) -> RadioRequest | None:
    words = [word for word in folded(command).split() if word not in _FILLERS]
    tokens = _tokens(command)
    if not words or not _about_radio(words, command):
        return None
    if _WHICH.search(" ".join(words)):
        return RadioRequest(RadioAction.NOW_PLAYING)
    if any(word.startswith("ses") for word in words) or "volume" in words or words[-1] in _QUIETER | {"up", "louder"}:
        if any(word in _QUIETER for word in words):
            return RadioRequest(RadioAction.QUIETER)
        if any(word in _LOUDER for word in words):
            return RadioRequest(RadioAction.LOUDER)
    if any(word in _STOP for word in words):
        return RadioRequest(RadioAction.STOP)
    if words[-1] in _PLAY:
        return RadioRequest(RadioAction.PLAY, _station(command, tokens[: _last_index(tokens, _PLAY)]))
    english = _english_play(words)
    if english is not None:
        return RadioRequest(RadioAction.PLAY, _station(command, tokens[english:]))
    return None


def _about_radio(words: list[str], command: str) -> bool:
    if radio_stations.mentioned(command) is not None:
        return True
    return any(word.startswith(("radyo", "radio")) or _cut(word) == "fm" for word in words) or bool(
        _WHICH.search(" ".join(words))
    )


def _tokens(command: str) -> list[str]:
    """The words as said, each cut at its apostrophe ("FM'i" → "FM"), without punctuation or fillers."""
    cut = (re.split(r"['’]", word)[0].strip('.,!?;:"') for word in command.split())
    return [word for word in cut if word and folded(word) not in _FILLERS]


def _cut(word: str) -> str:
    """ "fmi", "fmyi" → "fm": the case ending when the apostrophe was lost on the way."""
    return "fm" if re.fullmatch(r"fm(y?[iu])?", word) else word


def _last_index(tokens: list[str], verbs: frozenset[str]) -> int:
    for index in range(len(tokens) - 1, -1, -1):
        if folded(tokens[index]) in verbs:
            return index
    return len(tokens)


def _english_play(words: list[str]) -> int | None:
    """Where the station's name starts after "play", "turn on", "put on"; None when it isn't such a request."""
    for opener in _ENGLISH_PLAY:
        if tuple(words[: len(opener)]) == opener:
            return len(opener)
    return None


def _station(command: str, said: list[str]) -> str | None:
    listed = radio_stations.mentioned(command)
    if listed is not None:
        return listed.name
    name = [word for word in said if folded(word) not in ("on",)]
    generic = all(re.fullmatch(r"(radyo\w*|radio|fm)", _cut(folded(word))) for word in name)
    if not name or generic:
        return None
    if folded(name[-1]).startswith(("radyosu", "radyoyu")):
        name = [*name[:-1], name[-1][: len("radyo")]]
    return " ".join(name)
