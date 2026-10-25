"""Within the playing track and list: seeking, starting the track over, shuffle and repeat."""

from enum import StrEnum
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.desktop.base import Media, RepeatMode
from bilge.desktop.process import DesktopError, NotPossibleHere
from bilge.tools.base import Tool, ToolError
from bilge.tools.desktop.common import choice, failure, int_argument, integer, obj, string_argument

SEEK_STEP_SECONDS = 10
_MAX_SEEK_SECONDS = 3600


class PlaybackAction(StrEnum):
    SEEK = "seek"
    RESTART_TRACK = "restartTrack"
    SHUFFLE_ON = "shuffleOn"
    SHUFFLE_OFF = "shuffleOff"
    REPEAT_TRACK = "repeatTrack"
    REPEAT_ALL = "repeatAll"
    REPEAT_OFF = "repeatOff"


_REPEAT = {
    PlaybackAction.REPEAT_TRACK: RepeatMode.TRACK,
    PlaybackAction.REPEAT_ALL: RepeatMode.ALL,
    PlaybackAction.REPEAT_OFF: RepeatMode.OFF,
}

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "playback": "Açık çalarda ileri ya da geri sarar, parçayı baştan başlatır, karışık çalmayı ya da tekrarlamayı açıp kapatır.",
        "seconds": "Sadece 'seek' için kaç saniye; geri sarmak için eksi ('30 saniye geri' → -30)",
        "no_player": "Açık bir müzik çalar bulamadım.",
        "unsupported": "Çalar bunu desteklemiyor.",
        "forward": "{player} {amount} ileri sarıldı.",
        "back": "{player} {amount} geri sarıldı.",
        "seconds_amount": "{n} saniye", "minutes_amount": "{n} dakika", "mixed_amount": "{m} dakika {s} saniye",
        PlaybackAction.RESTART_TRACK: "Parça baştan başladı.",
        PlaybackAction.SHUFFLE_ON: "Karışık çalma açık.",
        PlaybackAction.SHUFFLE_OFF: "Karışık çalma kapalı.",
        PlaybackAction.REPEAT_TRACK: "Bu parça tekrarlanacak.",
        PlaybackAction.REPEAT_ALL: "Liste tekrarlanacak.",
        PlaybackAction.REPEAT_OFF: "Tekrarlama kapalı.",
    },
    AssistantLanguage.ENGLISH: {
        "playback": "In the open player: seeks forward or back, starts the track over, turns shuffle or repeat on or off.",
        "seconds": "Only for 'seek': how many seconds; negative to go back ('back 30 seconds' → -30)",
        "no_player": "I couldn't find an open music player.",
        "unsupported": "The player doesn't support that.",
        "forward": "Skipped {amount} ahead in {player}.",
        "back": "Went back {amount} in {player}.",
        "seconds_amount": "{n} seconds", "minutes_amount": "{n} minutes", "mixed_amount": "{m} minutes {s} seconds",
        "second_amount": "1 second", "minute_amount": "1 minute",
        PlaybackAction.RESTART_TRACK: "The track started over.",
        PlaybackAction.SHUFFLE_ON: "Shuffle is on.",
        PlaybackAction.SHUFFLE_OFF: "Shuffle is off.",
        PlaybackAction.REPEAT_TRACK: "This track will repeat.",
        PlaybackAction.REPEAT_ALL: "The list will repeat.",
        PlaybackAction.REPEAT_OFF: "Repeat is off.",
    },
}  # fmt: skip


def playback_tool(media: Media, language: AssistantLanguage) -> Tool:
    texts = _TEXTS[language]

    def act(action: PlaybackAction, seconds: int) -> str:
        if action is PlaybackAction.SEEK:
            return media.seek(seconds)
        if action is PlaybackAction.RESTART_TRACK:
            return media.restart_track()
        if action in (PlaybackAction.SHUFFLE_ON, PlaybackAction.SHUFFLE_OFF):
            return media.set_shuffle(action is PlaybackAction.SHUFFLE_ON)
        return media.set_repeat(_REPEAT[action])

    def run(arguments: dict[str, Any]) -> str:
        try:
            action = PlaybackAction(string_argument(arguments, "action"))
        except ValueError as error:
            raise ToolError(texts["unsupported"]) from error
        seconds = int_argument(arguments, "seconds") or SEEK_STEP_SECONDS
        seconds = max(-_MAX_SEEK_SECONDS, min(_MAX_SEEK_SECONDS, seconds))
        try:
            if media.now_playing() is None:
                return texts["no_player"]
            player = act(action, seconds)
        except NotPossibleHere as error:
            raise ToolError(texts["unsupported"]) from error
        except DesktopError as error:
            raise failure(error, language, texts["unsupported"]) from error
        if action is PlaybackAction.SEEK:
            key = "forward" if seconds > 0 else "back"
            return texts[key].format(player=player, amount=_amount(abs(seconds), texts))
        return texts[action]

    parameters = obj(
        ["action"], action=choice(PlaybackAction, ""),
        seconds=integer(texts["seconds"], -_MAX_SEEK_SECONDS, _MAX_SEEK_SECONDS),
    )  # fmt: skip
    return Tool("controlPlayback", texts["playback"], run=run, parameters=parameters)


def _amount(seconds: int, texts: dict[str, str]) -> str:
    minutes, rest = divmod(seconds, 60)
    if minutes and rest:
        return texts["mixed_amount"].format(m=minutes, s=rest)
    n, unit = (minutes, "minute") if minutes else (rest, "second")
    # English says "1 minute" but "2 minutes"; Turkish keeps the singular after a number.
    if n == 1 and f"{unit}_amount" in texts:
        return texts[f"{unit}_amount"]
    return texts[f"{unit}s_amount"].format(n=n)
