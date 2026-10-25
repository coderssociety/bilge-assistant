"""Volume and the music player."""

from enum import StrEnum
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.desktop.base import Media, MediaCommand, MusicLauncher, Volume
from bilge.desktop.process import DesktopError
from bilge.tools.base import Tool, ToolError
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
        "search": "Belirli bir sanatçıyı, şarkıyı ya da albümü bulup çalar ('Tarkan çal'): Spotify yüklüyse onda, değilse tarayıcıda YouTube Music'te arar.",
        "query": "Sanatçı, şarkı ya da albüm adı, söylendiği gibi",
        "no_query": "Ne çalmamı istediğini anlayamadım.",
        "searched": "{place} içinde '{query}' aramasını açtım; listeden bir şarkı seçebilirsin.",
        "nothing_playing": "Şu an çalan bir şey yok.",
        "now_playing": "Çalan: {song}.",
        MusicAction.PLAY: "{player} çalıyor.",
        MusicAction.PAUSE: "{player} duraklatıldı.",
        MusicAction.TOGGLE: "{player} oynat/duraklat yapıldı.",
        MusicAction.NEXT: "Sonraki parçaya geçildi.",
        MusicAction.PREVIOUS: "Önceki parçaya dönüldü.",
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
        "search": "Finds and plays a named artist, song or album ('play Tarkan'): in Spotify when it's installed, otherwise on YouTube Music in the browser.",
        "query": "The artist, song or album, as said",
        "no_query": "I didn't get what to play.",
        "searched": "I opened a search for '{query}' in {place}; pick a song from the list.",
        "nothing_playing": "Nothing is playing right now.",
        "now_playing": "Playing: {song}.",
        MusicAction.PLAY: "{player} is playing.",
        MusicAction.PAUSE: "{player} is paused.",
        MusicAction.TOGGLE: "Toggled play and pause in {player}.",
        MusicAction.NEXT: "Skipped to the next track.",
        MusicAction.PREVIOUS: "Went back to the previous track.",
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


def music_tool(media: Media, language: AssistantLanguage, launcher: MusicLauncher | None = None) -> Tool:
    texts = _TEXTS[language]

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
        except ValueError:
            action = MusicAction.TOGGLE
        try:
            if action is MusicAction.NOW_PLAYING:
                playing = media.now_playing()
                if playing is None:
                    return texts["no_player"]
                if not playing.playing or not playing.title:
                    return texts["nothing_playing"]
                song = f"{playing.title} - {playing.artist}" if playing.artist else playing.title
                return texts["now_playing"].format(song=song)
            if media.now_playing() is None:
                return start() if action in (MusicAction.PLAY, MusicAction.TOGGLE) else texts["no_player"]
            player = media.send(MediaCommand(action.value))
        except DesktopError as error:
            raise failure(error, language) from error
        return texts[action].format(player=player)

    # Track titles can be set by whoever made the video or page that is playing.
    return Tool("controlMusic", texts["music"], run=run, parameters=obj(["action"], action=choice(MusicAction, "")),
                untrusted_output=lambda arguments: arguments.get("action") == MusicAction.NOW_PLAYING)  # fmt: skip


def music_search_tool(launcher: MusicLauncher, language: AssistantLanguage) -> Tool:
    texts = _TEXTS[language]

    def run(arguments: dict[str, Any]) -> str:
        query = string_argument(arguments, "query")
        if not query:
            raise ToolError(texts["no_query"])
        try:
            place = launcher.play_search(query)
        except DesktopError as error:
            raise failure(error, language) from error
        return texts["searched"].format(place=place, query=query)

    return Tool("playMusic", texts["search"], run=run, parameters=obj(["query"], query=text(texts["query"])))
