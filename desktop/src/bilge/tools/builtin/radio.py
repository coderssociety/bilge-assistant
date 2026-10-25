"""Radio played inside Bilge: "radyo aç", "Power FM aç", "radyoyu kapat", "radyonun sesini kıs", "hangi radyo
çalıyor". Stations come from radio-browser.info's public list; the last one played is remembered."""

import json
import logging
from pathlib import Path
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.core.media import radio_request, radio_stations
from bilge.core.media.playback_state import Kind, Source
from bilge.core.media.radio_request import RadioAction
from bilge.core.text import folded
from bilge.tools import web_fetch
from bilge.tools.base import Tool, ToolError
from bilge.tools.feed_cache import TimedCache, get_json
from bilge.tools.player import PlaybackError, Player, failure

log = logging.getLogger(__name__)
# Mirrors of the same list; the next is asked when one doesn't answer.
HOSTS = (
    "https://de1.api.radio-browser.info",
    "https://de2.api.radio-browser.info",
    "https://all.api.radio-browser.info",
)
SEARCH_PATH = "/json/stations/search?"
CACHE_SECONDS = 3600
# Other listings of the same station tried when one won't start (a dead server, a broken certificate chain).
STREAMS_TRIED = 3

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "tool": "Bilge'nin içinde radyo çalar: bir istasyonu açar ('Power FM aç', 'radyo aç' son dinleneni açar), "
        "kapatır, radyonun sesini kısar ya da açar, hangi istasyonun çaldığını söyler.",
        "station": "İstasyon adı, söylendiği gibi ('TRT FM'); 'radyo aç' gibi ad yoksa boş bırak",
        "playing": "{name} açıldı.",
        "not_found": "'{name}' adında bir radyo istasyonu bulamadım.",
        "lookup_failed": "Radyo listesine ulaşamadım. ",
        "connect_failed": "{name} yayınına bağlanamadım. ",
        "stopped": "Radyoyu kapattım.",
        "not_playing": "Şu an radyo çalmıyor.",
        "level": "Radyonun sesi yüzde {level}.",
        "quietest": "Radyonun sesi zaten en kısık.",
        "loudest": "Radyonun sesi zaten en açık.",
        "now": "{name} çalıyor.",
        "paused": "{name} duraklatılmış.",
        "ask_play": "{name} açayım mı?",
        "ask_stop": "Radyoyu kapatayım mı?",
        "ask_quieter": "Radyonun sesini kısayım mı?",
        "ask_louder": "Radyonun sesini açayım mı?",
        "ask_nowPlaying": "Hangi istasyonun çaldığını söyleyeyim mi?",
    },
    AssistantLanguage.ENGLISH: {
        "tool": "Plays radio inside Bilge: starts a station ('play Power FM'; 'play the radio' starts the last one), "
        "stops it, turns the radio down or up, or says which station is on.",
        "station": "The station's name as said ('TRT FM'); empty for just 'the radio'",
        "playing": "Playing {name}.",
        "not_found": "I couldn't find a radio station called '{name}'.",
        "lookup_failed": "I couldn't reach the radio station list. ",
        "connect_failed": "I couldn't connect to {name}. ",
        "stopped": "The radio is off.",
        "not_playing": "The radio isn't on.",
        "level": "The radio is at {level} percent.",
        "quietest": "The radio is already as low as it goes.",
        "loudest": "The radio is already as loud as it goes.",
        "now": "{name} is on.",
        "paused": "{name} is paused.",
        "ask_play": "Shall I play {name}?",
        "ask_stop": "Shall I turn the radio off?",
        "ask_quieter": "Shall I turn the radio down?",
        "ask_louder": "Shall I turn the radio up?",
        "ask_nowPlaying": "Shall I say which station is on?",
    },
}


class StationMemory:
    """The last station played, kept across restarts; a missing or broken file just means none yet."""

    def __init__(self, path: Path | None) -> None:
        self._path = path
        self._name: str | None = None
        if path is not None and path.exists():
            try:
                stored = json.loads(path.read_text(encoding="utf-8")).get("station")
                self._name = stored if isinstance(stored, str) and stored.strip() else None
            except (OSError, ValueError, AttributeError):
                log.info("Could not read the last radio station", exc_info=True)

    @property
    def last(self) -> str | None:
        return self._name

    def remember(self, name: str) -> None:
        self._name = name
        if self._path is None:
            return
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
            self._path.write_text(json.dumps({"station": name}, ensure_ascii=False), encoding="utf-8")
        except OSError:
            log.info("Could not keep the last radio station", exc_info=True)


def find_streams(name: str, language: AssistantLanguage) -> list[radio_stations.Stream]:
    """Turkish stations first, then any country's; each search goes to the next mirror when one fails."""
    listed = radio_stations.mentioned(name)
    term = listed.search if listed else name
    for country in ("TR", None):
        streams = radio_stations.ranked(_search(radio_stations.search_query(term, country), language), term)
        if streams:
            return streams
    return []


def _search(fields: str, language: AssistantLanguage) -> Any:
    last: web_fetch.WebFetchError | None = None
    # The mirrors share a network, and a moment's failure often hits them all: they get a second round.
    for host in (*HOSTS, *HOSTS):
        try:
            return get_json(host + SEARCH_PATH + fields, language)
        except web_fetch.WebFetchError as error:
            last = error
    raise last or web_fetch.WebFetchError(web_fetch.Reason.UNEXPECTED)


def claims(command: str) -> bool:
    return radio_request.parse(command) is not None


def rule_arguments(command: str) -> dict[str, Any]:
    request = radio_request.parse(command)
    if request is None:
        return {}
    return {"action": request.action.value, **({"station": request.station} if request.station else {})}


def radio_tool(
    language: AssistantLanguage, player: Player, memory: StationMemory, cache: TimedCache | None = None
) -> Tool:
    texts = _TEXTS[language]
    cache = cache or TimedCache()

    def on_air() -> Source | None:
        playback = player.playback
        return playback.source if playback.is_active and playback.source and playback.source.is_live else None

    def play(name: str) -> str:
        try:
            streams = cache.get(folded(name), CACHE_SECONDS, lambda: find_streams(name, language))
        except web_fetch.WebFetchError as error:
            raise ToolError(texts["lookup_failed"] + web_fetch.describe(error, language)) from error
        if not streams:
            raise ToolError(texts["not_found"].format(name=name))
        failed: PlaybackError | None = None
        for stream in streams[:STREAMS_TRIED]:
            try:
                player.play(Source(Kind.RADIO, name, stream.url, stream.is_playlist))
            except PlaybackError as error:
                failed = error
                continue
            memory.remember(name)
            return texts["playing"].format(name=name)
        raise ToolError(texts["connect_failed"].format(name=name) + failure(failed, language)) from failed

    def run(arguments: dict[str, Any]) -> str:
        try:
            action = RadioAction(str(arguments.get("action") or RadioAction.PLAY))
        except ValueError:
            action = RadioAction.PLAY
        if action is RadioAction.PLAY:
            said = str(arguments.get("station") or "").strip()
            return play(said or memory.last or radio_stations.DEFAULT.name)
        source = on_air()
        if source is None:
            return texts["not_playing"]
        if action is RadioAction.STOP:
            player.stop()
            return texts["stopped"]
        if action is RadioAction.NOW_PLAYING:
            return texts["now" if player.playback.is_playing else "paused"].format(name=source.name)
        before = player.playback.volume
        after = (player.louder() if action is RadioAction.LOUDER else player.quieter()).volume
        if after == before:
            return texts["loudest" if action is RadioAction.LOUDER else "quietest"]
        return texts["level"].format(level=round(after * 100))

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        """What the rule reads from the command wins over the model's guess."""
        return rule_arguments(command) or arguments

    parameters = {
        "type": "object",
        "properties": {
            "action": {"type": "string", "enum": [action.value for action in RadioAction]},
            "station": {"type": "string", "description": texts["station"]},
        },
        "required": ["action"],
    }

    def spoken_action(arguments: dict[str, Any]) -> str:
        key = f"ask_{arguments.get('action')}"
        if key not in texts or key == "ask_play":
            return texts["ask_play"].format(name=arguments.get("station") or memory.last or radio_stations.DEFAULT.name)
        return texts[key]

    return Tool("radio", texts["tool"], run=run, parameters=parameters, refine=refine, spoken_action=spoken_action)
