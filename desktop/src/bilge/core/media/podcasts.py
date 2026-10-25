"""Podcast requests ("Fularsız Entellik podcastinin son bölümünü aç", "Nasıl Olunur'un yeni bölümü var mı", "play the
latest episode of X"), the show to take from Apple's podcast search, and its newest episode from the feed."""

import re
from dataclasses import dataclass
from enum import StrEnum
from typing import Any
from urllib.parse import urlencode, urlsplit

from bilge.core.text import folded
from bilge.core.web.rss_headlines import Item


class PodcastAction(StrEnum):
    LATEST = "latest"
    CHECK = "check"


@dataclass(frozen=True)
class PodcastRequest:
    action: PodcastAction
    name: str


_PLAY = frozenset({"ac", "cal", "oynat", "baslat", "dinlet", "acar", "calar", "play"})
_FILLERS = frozenset({"bilge", "lutfen", "misin", "musun", "bakalim", "hadi", "please"})
# Where the show's name ends: "X podcastinin…", "X'in son bölümü…", "X'in yeni bölümü…".
_NAME_ENDS = re.compile(r"^(podcast\w*|podkast\w*|bolum\w*|son|yeni|en)$")
_SHOW = re.compile(r"\b(podcast|podkast)\w*|\bepisodes?\b")
_EPISODE = re.compile(r"\bbolum\w*")
_QUESTION = re.compile(r"\b(var mi|cikti mi|geldi mi|yayinlandi mi|is there|are there|any new|has .* new)\b")
_ENGLISH_NAME = re.compile(r"\b(?:episodes? of|from) (.+)$", re.IGNORECASE)
# Genitive endings an unknown name may carry when the apostrophe was lost ("Fularsız Entellikin").
_GENITIVE = re.compile(r"(nin|nın|nun|nün|in|ın|un|ün)$")


def parse(command: str) -> PodcastRequest | None:
    words = [word for word in folded(command).split() if word not in _FILLERS]
    phrase = " ".join(words)
    show = _SHOW.search(phrase) is not None
    if not words or not (show or _EPISODE.search(phrase)):
        return None
    if _QUESTION.search(phrase) and ("yeni" in words or "new" in words):
        action = PodcastAction.CHECK
    elif show and (words[-1] in _PLAY or words[0] == "play"):
        # Without "podcast" an episode could be a series' ("Medcezir'in son bölümü"); the model decides those.
        action = PodcastAction.LATEST
    else:
        return None
    name = _name(command)
    return PodcastRequest(action, name) if name else None


def _name(command: str) -> str:
    english = _ENGLISH_NAME.search(command.strip(" ?.!"))
    if english:
        return english.group(1).strip()
    said = [word.strip('.,!?;:"') for word in command.split()]
    said = [word for word in said if folded(word) not in _FILLERS]
    if said and folded(said[0]) == "play":
        said = said[1:]
    name: list[str] = []
    for word in said:
        # "Yeni Bir Gün podcastini aç": a show may start with "yeni" or "son"; "podcast" and "bölüm" always end it.
        if _NAME_ENDS.match(folded(word)) and (name or folded(word).startswith(("podcast", "podkast", "bolum"))):
            break
        name.append(word)
        if re.search(r"['’]", word):
            break
    if all(_NAME_ENDS.match(folded(word)) for word in name):
        return ""
    return " ".join(re.split(r"['’]", " ".join(name))[0].split()).strip()


def search_terms(name: str) -> list[str]:
    """The name as said, then without a genitive ending the recognizer may have glued on."""
    stripped = _GENITIVE.sub("", name) if len(name.split()[-1]) > 5 else name
    return list(dict.fromkeys([name, stripped]))


def search_query(term: str, country: str = "tr") -> str:
    return urlencode({"media": "podcast", "term": term, "country": country, "limit": "10"})


@dataclass(frozen=True)
class Show:
    name: str
    feed: str


def choose(results: Any, name: str) -> Show | None:
    """The show whose title is the name said, else the one starting with it, else the search's first."""
    shows = []
    for entry in results.get("results", []) if isinstance(results, dict) else []:
        if not isinstance(entry, dict):
            continue
        feed = str(entry.get("feedUrl") or "")
        title = str(entry.get("collectionName") or "")
        if title and urlsplit(feed).scheme in ("http", "https"):
            shows.append(Show(title, feed))
    wanted = folded(name)
    for matches in (lambda title: title == wanted, lambda title: title.startswith(wanted)):
        found = next((show for show in shows if matches(folded(show.name))), None)
        if found is not None:
            return found
    return shows[0] if shows else None


def latest(episodes: list[Item]) -> Item | None:
    """The newest item with audio attached; feeds list newest first, but not all of them."""
    playable = [item for item in episodes if item.enclosure]
    dated = [item for item in playable if item.published is not None]
    if dated:
        return max(dated, key=lambda item: item.published)
    return playable[0] if playable else None
