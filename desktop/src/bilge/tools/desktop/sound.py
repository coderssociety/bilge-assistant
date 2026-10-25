"""Volume, the music player, and playing a named song on a music service."""

import logging
from collections.abc import Callable
from enum import StrEnum
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.core.media import music_request, music_search, track_name
from bilge.core.media.music_request import MusicService
from bilge.core.media.music_search import Track
from bilge.desktop.base import Media, MediaCommand, MusicLauncher, Volume
from bilge.desktop.process import DesktopError
from bilge.tools import music_lookup
from bilge.tools.base import Tool, ToolError
from bilge.tools.desktop import sources
from bilge.tools.desktop.common import (
    choice,
    failure,
    int_argument,
    integer,
    obj,
    refine_level,
    string_argument,
    text,
)
from bilge.tools.player import PlaybackError, Player
from bilge.tools.player import failure as playback_failure
from bilge.tools.web_fetch import WebFetchError

log = logging.getLogger(__name__)

VOLUME_STEP = 10


class VolumeAction(StrEnum):
    SET = "set"
    INCREASE = "increase"
    DECREASE = "decrease"
    MUTE = "mute"
    UNMUTE = "unmute"


class MusicAction(StrEnum):
    PLAY = "play"
    PAUSE = "pause"
    TOGGLE = "toggle"
    NEXT = "next"
    PREVIOUS = "previous"
    NOW_PLAYING = "nowPlaying"


_TEXTS = {
    AssistantLanguage.TURKISH: {
        "volume": "Bilgisayarın ses seviyesini ayarlar, artırır, azaltır, sessize alır ya da sesi açar.",
        "level": "Sadece 'set' için hedef seviye (0-100)",
        "by": "Sadece 'increase'/'decrease' için kaç puan; söylenmediyse boş bırak ('yüzde 20 artır' → 20)",
        "no_level": "Hedef seviye belirtilmedi.",
        "level_now": "Ses seviyesi yüzde {level}.",
        "muted": "Ses kapatıldı.",
        "unmuted": "Ses açıldı, seviye yüzde {level}.",
        "music": "Açık müzik ya da video çaların (Spotify, Rhythmbox, VLC, tarayıcı) çalmasını başlatır, duraklatır, sonraki/önceki parçaya geçer ya da çalanı söyler.",
        "no_player": "Açık bir müzik çalar bulamadım.",
        "no_player_installed": "Yüklü bir müzik çalar bulamadım. Spotify, Rhythmbox ya da VLC gibi bir çalar kurup açtıktan sonra tekrar söyle.",
        "started_playing": "{player} açıldı ve çalıyor.",
        "started_idle": "{player} açıldı ama çalmayı başlatamadım; çalardan bir şarkı seçebilirsin.",
        "search": "Belirli bir sanatçıyı, şarkıyı ya da albümü bulup çalar ('Tarkan çal', 'YouTube'da Kuzu Kuzu aç'): söylenen serviste, söylenmediyse ayarlardaki serviste ilk eşleşen şarkıyı açar.",
        "query": "Sanatçı, şarkı ya da albüm adı, söylendiği gibi",
        "service": "Sadece servis söylendiyse: spotify, youtube, youtube_music, deezer ya da apple_music",
        "no_query": "Ne çalmamı istediğini anlayamadım.",
        "opened": "{place} '{song}' açıldı.",
        "searched": "{place} '{query}' aramasını açtım; listeden bir şarkı seçebilirsin.",
        "not_found": "{place} '{query}' için bir şarkı bulamadım; arama sayfasını açtım.",
        "unreachable": "{place} şarkıyı arayamadım; '{query}' arama sayfasını açtım.",
        "nothing_playing": "Şu an çalan bir şey yok.",
        "now_playing": "Çalan: {song}.",
        MusicAction.PLAY: "{player} çalıyor.",
        MusicAction.PAUSE: "{player} duraklatıldı.",
        MusicAction.TOGGLE: "{player} oynat/duraklat yapıldı.",
        MusicAction.NEXT: "Sonraki parçaya geçildi.",
        MusicAction.PREVIOUS: "Önceki parçaya dönüldü.",
        "own_paused": "{name} duraklatıldı.",
        "own_stopped": "{name} kapatıldı.",
        "own_resumed": "{name} devam ediyor.",
        "own_playing": "{name} zaten çalıyor.",
        "own_station": "{name} radyosu çalıyor.",
        "own_episode": "{name} podcasti çalıyor: {title}",
        "own_no_skip": "Bunda parça atlanamıyor; başka bir istasyon ya da bölüm isteyebilirsin.",
        "own_failed": "{name} yeniden açılamadı. ",
        "unknown_action": "Müzik çalarda bunu yapamıyorum; çalabilir, duraklatabilir ya da parça atlayabilirim.",
    },
    AssistantLanguage.ENGLISH: {
        "volume": "Sets, raises or lowers the computer's volume, or mutes and unmutes it.",
        "level": "Only for 'set': the target level (0-100)",
        "by": "Only for 'increase'/'decrease': by how many points; leave empty if not said ('up by 20' → 20)",
        "no_level": "No target level was given.",
        "level_now": "The volume is at {level} percent.",
        "muted": "Sound is muted.",
        "unmuted": "Sound is back on, at {level} percent.",
        "music": "Plays, pauses, skips or goes back in the open music or video player (Spotify, Rhythmbox, VLC, a browser), or says what is playing.",
        "no_player": "I couldn't find an open music player.",
        "no_player_installed": "I couldn't find a music player. Install one such as Spotify, Rhythmbox or VLC, open it, and ask again.",
        "started_playing": "{player} is open and playing.",
        "started_idle": "{player} is open, but I couldn't start playback; pick a song there.",
        "search": "Finds and plays a named artist, song or album ('play Tarkan', 'play Kuzu Kuzu on YouTube'): opens the first matching song on the service named, or else on the one chosen in the settings.",
        "query": "The artist, song or album, as said",
        "service": "Only when a service was named: spotify, youtube, youtube_music, deezer or apple_music",
        "no_query": "I didn't get what to play.",
        "opened": "Opened '{song}' on {place}.",
        "searched": "I opened a search for '{query}' in {place}; pick a song from the list.",
        "not_found": "I couldn't find a song for '{query}' on {place}, so I opened its search page.",
        "unreachable": "I couldn't search {place}, so I opened its search page for '{query}'.",
        "nothing_playing": "Nothing is playing right now.",
        "now_playing": "Playing: {song}.",
        MusicAction.PLAY: "{player} is playing.",
        MusicAction.PAUSE: "{player} is paused.",
        MusicAction.TOGGLE: "Toggled play and pause in {player}.",
        MusicAction.NEXT: "Skipped to the next track.",
        MusicAction.PREVIOUS: "Went back to the previous track.",
        "own_paused": "{name} is paused.",
        "own_stopped": "{name} is off.",
        "own_resumed": "{name} is playing again.",
        "own_playing": "{name} is already playing.",
        "own_station": "{name} is on.",
        "own_episode": "Playing {name}: {title}",
        "own_no_skip": "There are no tracks to skip here; ask for another station or episode instead.",
        "own_failed": "I couldn't start {name} again. ",
        "unknown_action": "I can't do that in the music player; I can play, pause or skip tracks.",
    },
}


def volume_tool(volume: Volume, language: AssistantLanguage) -> Tool:
    texts = _TEXTS[language]

    def run(arguments: dict[str, Any]) -> str:
        action = string_argument(arguments, "action")
        level = int_argument(arguments, "level")
        by = int_argument(arguments, "by")
        try:
            if action == VolumeAction.MUTE:
                volume.set_muted(True)
                return texts["muted"]
            state = volume.state() if action == VolumeAction.UNMUTE else None
            if state is not None and state.muted:
                volume.set_muted(False)
                return texts["unmuted"].format(level=state.level)
            if action == VolumeAction.UNMUTE:
                # "Sesi aç" with the sound already on means louder.
                action = VolumeAction.INCREASE
            if action == VolumeAction.SET:
                if level is None:
                    raise ToolError(texts["no_level"])
                target = level
            elif action in (VolumeAction.INCREASE, VolumeAction.DECREASE):
                amount = by if by is not None and by > 0 else VOLUME_STEP
                step = amount if action == VolumeAction.INCREASE else -amount
                target = (state or volume.state()).level + step
            else:
                raise ToolError(texts["no_level"])
            target = max(0, min(100, target))
            volume.set_level(target)
            return texts["level_now"].format(level=target)
        except DesktopError as error:
            raise failure(error, language) from error

    parameters = obj(
        ["action"], action=choice(VolumeAction, "set/increase/decrease/mute/unmute"),
        level=integer(texts["level"], 0, 100), by=integer(texts["by"], 1, 100),
    )  # fmt: skip
    return Tool("setVolume", texts["volume"], run=run, parameters=parameters, refine=refine_level)


def music_tool(
    media: Media, language: AssistantLanguage, launcher: MusicLauncher | None = None, player: Player | None = None
) -> Tool:
    """`player`: Bilge's own radio and podcast player, which "durdur" and "devam et" reach first while it plays."""
    texts = _TEXTS[language]

    def own(action: MusicAction) -> str | None:
        playback = player.playback if player is not None else None
        if playback is None or not playback.is_active or playback.source is None:
            return None
        source = playback.source
        if not playback.is_playing:
            # A song the user paused in the desktop player since is what "devam et" means now.
            if action not in (MusicAction.PLAY, MusicAction.TOGGLE) or sources.desktop_holds_track(media):
                return None
            try:
                player.resume()
            except PlaybackError as error:
                raise ToolError(
                    texts["own_failed"].format(name=source.name) + playback_failure(error, language)
                ) from error
            return texts["own_resumed"].format(name=source.name)
        if action is MusicAction.PLAY:
            # With a song waiting in the desktop player, "müziği aç" means that song rather than the station on.
            return None if sources.desktop_holds_track(media) else texts["own_playing"].format(name=source.name)
        if action in (MusicAction.PAUSE, MusicAction.TOGGLE):
            player.pause()
            # A station can't wait: pausing it lets it go, and "devam et" tunes in again.
            return texts["own_stopped" if source.is_live else "own_paused"].format(name=source.name)
        if action is MusicAction.NOW_PLAYING:
            if source.is_live or not source.title:
                return texts["own_station"].format(name=source.name)
            return texts["own_episode"].format(name=source.name, title=source.title)
        return texts["own_no_skip"]

    def start() -> str:
        """Play with no player open: start the user's player rather than give up."""
        if launcher is None:
            return texts["no_player"]
        started = launcher.start_player()
        if started is None:
            return texts["no_player_installed"]
        return texts["started_playing" if started.playing else "started_idle"].format(player=started.name)

    def run(arguments: dict[str, Any]) -> str:
        try:
            action = MusicAction(string_argument(arguments, "action"))
        except ValueError as error:
            raise ToolError(texts["unknown_action"]) from error
        handled = own(action)
        if handled is not None:
            return handled
        if action in (MusicAction.PLAY, MusicAction.TOGGLE):
            sources.quiet_own(player)
        try:
            if action is MusicAction.NOW_PLAYING:
                playing = media.now_playing()
                if playing is None:
                    return texts["no_player"]
                if not playing.playing or not playing.title:
                    return texts["nothing_playing"]
                title, artist = track_name.cleaned(playing.title, playing.artist)
                song = f"{title} - {artist}" if artist else title
                return texts["now_playing"].format(song=song)
            if media.now_playing() is None:
                return start() if action in (MusicAction.PLAY, MusicAction.TOGGLE) else texts["no_player"]
            name = media.send(MediaCommand(action.value))
        except DesktopError as error:
            raise failure(error, language) from error
        return texts[action].format(player=name)

    # Track titles can be set by whoever made the video or page that is playing.
    return Tool("controlMusic", texts["music"], run=run, parameters=obj(["action"], action=choice(MusicAction, "")),
                untrusted_output=lambda arguments: arguments.get("action") == MusicAction.NOW_PLAYING)  # fmt: skip


def music_claims(command: str) -> bool:
    return music_request.parse(command) is not None


def music_rule_arguments(command: str) -> dict[str, Any]:
    request = music_request.parse(command)
    return {"query": request.query, "service": request.service.value} if request else {}


def music_search_tool(
    launcher: MusicLauncher,
    language: AssistantLanguage,
    default_service: Callable[[], str] = lambda: music_request.AUTO,
    find: Callable[[MusicService, str, AssistantLanguage], list[Track]] = music_lookup.find,
    player: Player | None = None,
) -> Tool:
    """`default_service`: the setting used when the command names no service. `player`: Bilge's own radio and podcast
    player, quieted before the song opens so the two don't play over each other."""
    texts = _TEXTS[language]
    places = music_request.LOCATIVES if language is AssistantLanguage.TURKISH else music_request.NAMES
    region = music_lookup.country(language)

    def play(service: MusicService, query: str) -> str:
        place = places[service]
        if service is MusicService.SPOTIFY:
            # Spotify has no keyless search to pick a song with.
            in_app = launcher.has_app(service)
            launcher.open(
                music_search.spotify_search(query) if in_app else music_search.search_page(service, query, region)
            )
            return texts["searched"].format(place=place, query=query)
        try:
            found = find(service, query, language)
        except WebFetchError as error:
            log.info("Could not search %s: %s", service.value, error)
            launcher.open(music_search.search_page(service, query, region))
            return texts["unreachable"].format(place=place, query=query)
        if not found:
            launcher.open(music_search.search_page(service, query, region))
            return texts["not_found"].format(place=place, query=query)
        track = found[0]
        in_app = service is MusicService.DEEZER and launcher.has_app(service)
        launcher.open(music_search.deezer_app_url(track) if in_app else track.url)
        return texts["opened"].format(place=place, song=track.spoken)

    def run(arguments: dict[str, Any]) -> str:
        query = string_argument(arguments, "query")
        if not query:
            raise ToolError(texts["no_query"])
        try:
            service = music_request.chosen_service(
                string_argument(arguments, "service") or None,
                default_service(),
                lambda: launcher.has_app(MusicService.SPOTIFY),
            )
            sources.quiet_own(player)
            return play(service, query)
        except DesktopError as error:
            raise failure(error, language) from error

    parameters = obj(["query"], query=text(texts["query"]), service=choice(MusicService, texts["service"]))
    # The song's title is written by whoever uploaded it.
    return Tool("playMusic", texts["search"], run=run, parameters=parameters, untrusted_output=True)
