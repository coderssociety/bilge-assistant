"""Podcasts played inside Bilge: "X podcastinin son bölümünü aç" plays the newest episode, "Y'nin yeni bölümü var
mı" says when the last one came out. Shows are found with Apple's podcast search and read from their own feeds."""

from collections.abc import Callable
from datetime import datetime
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.core.media import podcasts
from bilge.core.media.playback_state import Kind, Source
from bilge.core.media.podcasts import PodcastAction
from bilge.core.web import rss_headlines
from bilge.core.web.spoken_dates import dated_phrase
from bilge.tools import web_fetch
from bilge.tools.base import Tool, ToolError
from bilge.tools.feed_cache import get_json
from bilge.tools.player import PlaybackError, Player, failure

SEARCH_URL = "https://itunes.apple.com/search?"
# Long-running shows have feeds of several megabytes.
FEED_BYTES = 12_000_000
FEED_ITEMS = 300
NEW_DAYS = 7

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "tool": "Podcast'leri Bilge'nin içinde çalar: bir podcast'in son bölümünü açar ('X podcastinin son bölümünü "
        "aç') ya da yeni bölüm çıkıp çıkmadığını söyler ('Y'nin yeni bölümü var mı'). Duraklatma, devam ettirme ve "
        "ileri/geri sarma müzik ve oynatma araçlarıyla yapılır.",
        "podcast": "Podcast'in adı, söylendiği gibi",
        "no_name": "Hangi podcast?",
        "not_found": "'{name}' adında bir podcast bulamadım.",
        "search_failed": "Podcast aramasına ulaşamadım. ",
        "feed_failed": "{name} podcastinin bölüm listesini alamadım. ",
        "no_episodes": "{name} podcastinde çalınabilecek bir bölüm bulamadım.",
        "connect_failed": "Bölümü açamadım. ",
        "playing": "{name} podcastinin son bölümü çalıyor ({day} yayımlandı).",
        "playing_undated": "{name} podcastinin son bölümü çalıyor.",
        "new": "Evet, {name} podcastinin yeni bölümü {day} yayımlandı: {title}",
        "not_new": "Son bir haftada yeni bölüm yok. {name} podcastinin son bölümü {day} yayımlandı: {title}",
        "undated": "{name} podcastinin en son bölümü: {title}",
        "ask_latest": "{name} podcastinin son bölümünü açayım mı?",
        "ask_check": "{name} podcastinde yeni bölüm var mı bakayım mı?",
    },
    AssistantLanguage.ENGLISH: {
        "tool": "Plays podcasts inside Bilge: the latest episode of a show ('play the latest episode of X'), or "
        "whether a new one is out ('is there a new episode of Y'). Pausing, resuming and skipping go through the "
        "music and playback tools.",
        "podcast": "The podcast's name, as said",
        "no_name": "Which podcast?",
        "not_found": "I couldn't find a podcast called '{name}'.",
        "search_failed": "I couldn't reach the podcast search. ",
        "feed_failed": "I couldn't get the episode list of {name}. ",
        "no_episodes": "I couldn't find an episode of {name} that I can play.",
        "connect_failed": "I couldn't open the episode. ",
        "playing": "Playing the latest episode of {name}, out {day}.",
        "playing_undated": "Playing the latest episode of {name}.",
        "new": "Yes, a new episode of {name} came out {day}: {title}",
        "not_new": "Nothing new this week. The latest episode of {name} came out {day}: {title}",
        "undated": "The latest episode of {name}: {title}",
        "ask_latest": "Shall I play the latest episode of {name}?",
        "ask_check": "Shall I look for a new episode of {name}?",
    },
}


def _local_now() -> datetime:
    return datetime.now().astimezone()


def claims(command: str) -> bool:
    return podcasts.parse(command) is not None


def rule_arguments(command: str) -> dict[str, Any]:
    request = podcasts.parse(command)
    return {"action": request.action.value, "podcast": request.name} if request else {}


def find_show(name: str, language: AssistantLanguage) -> tuple[str, podcasts.Show] | None:
    """The show and the spelling that found it, which is the one said back."""
    for term in podcasts.search_terms(name):
        show = podcasts.choose(get_json(SEARCH_URL + podcasts.search_query(term), language), term)
        if show is not None:
            return term, show
    return None


def newest_episode(show: podcasts.Show, language: AssistantLanguage) -> rss_headlines.Item | None:
    response = web_fetch.get(show.feed, language, max_bytes=FEED_BYTES)
    if response.status != 200:
        raise web_fetch.WebFetchError(web_fetch.Reason.STATUS, response.status)
    return podcasts.latest(rss_headlines.items(response.body, FEED_ITEMS))


def podcast_tool(language: AssistantLanguage, player: Player, clock: Callable[[], datetime] = _local_now) -> Tool:
    texts = _TEXTS[language]

    def episode_of(said: str) -> tuple[str, rss_headlines.Item]:
        try:
            found = find_show(said, language)
        except web_fetch.WebFetchError as error:
            raise ToolError(texts["search_failed"] + web_fetch.describe(error, language)) from error
        if found is None:
            raise ToolError(texts["not_found"].format(name=said))
        name, show = found
        try:
            episode = newest_episode(show, language)
        except web_fetch.WebFetchError as error:
            raise ToolError(texts["feed_failed"].format(name=name) + web_fetch.describe(error, language)) from error
        if episode is None:
            raise ToolError(texts["no_episodes"].format(name=name))
        return name, episode

    def run(arguments: dict[str, Any]) -> str:
        # The name is said back as the user said it: the show's own title is written by whoever made it.
        said = str(arguments.get("podcast") or "").strip()
        if not said:
            raise ToolError(texts["no_name"])
        name, episode = episode_of(said)
        now = clock()
        day = dated_phrase(episode.published.astimezone(now.tzinfo), now, language) if episode.published else None
        if arguments.get("action") == PodcastAction.CHECK:
            if day is None:
                return texts["undated"].format(name=name, title=episode.title)
            fresh = (now - episode.published).days < NEW_DAYS
            return texts["new" if fresh else "not_new"].format(name=name, day=day, title=episode.title)
        try:
            player.play(Source(Kind.EPISODE, name, episode.enclosure or "", title=episode.title))
        except PlaybackError as error:
            raise ToolError(texts["connect_failed"] + failure(error, language)) from error
        return texts["playing" if day else "playing_undated"].format(name=name, day=day)

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        return rule_arguments(command) or arguments

    parameters = {
        "type": "object",
        "properties": {
            "action": {"type": "string", "enum": [action.value for action in PodcastAction]},
            "podcast": {"type": "string", "description": texts["podcast"]},
        },
        "required": ["action", "podcast"],
    }

    # Only the check reads an episode title out; playing says the name the user gave.
    def spoken_action(arguments: dict[str, Any]) -> str:
        key = "ask_check" if arguments.get("action") == PodcastAction.CHECK else "ask_latest"
        return texts[key].format(name=arguments.get("podcast") or "")

    return Tool("podcast", texts["tool"], run=run, parameters=parameters, refine=refine, spoken_action=spoken_action,
                untrusted_output=lambda arguments: arguments.get("action") == PodcastAction.CHECK)  # fmt: skip
