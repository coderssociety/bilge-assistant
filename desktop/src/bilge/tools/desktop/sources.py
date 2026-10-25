"""Bilge's own radio and podcast player and the desktop's music player take turns: starting one quiets the other, so
two sources never play over each other, and a command that names neither goes to the one holding a song."""

import logging

from bilge.core.media.playback_state import Playback, Source
from bilge.desktop.base import Media, MediaCommand
from bilge.desktop.process import DesktopError
from bilge.tools.player import Player

log = logging.getLogger(__name__)


def desktop_holds_track(media: Media) -> bool:
    """A desktop player has a song loaded, playing or paused: "devam et" or "geri sar" is meant for it."""
    try:
        playing = media.now_playing()
    except DesktopError as error:
        log.info("Could not ask the desktop player what it holds: %s", error)
        return False
    return playing is not None and (playing.playing or bool(playing.title))


def pause_desktop(media: Media) -> None:
    try:
        playing = media.now_playing()
        if playing is not None and playing.playing:
            media.send(MediaCommand.PAUSE)
    except DesktopError as error:
        log.info("Could not pause the desktop player: %s", error)


def quiet_own(player: Player | None) -> None:
    """A station is let go, since it can't wait; an episode is paused and keeps its place."""
    if player is None or not player.playback.is_playing or player.playback.source is None:
        return
    if player.playback.source.is_live:
        player.stop()
    else:
        player.pause()


class TurnTakingPlayer:
    """Bilge's player as the tools use it: once its stream has really started, the desktop player is paused."""

    def __init__(self, player: Player, media: Media):
        self._player = player
        self._media = media

    @property
    def playback(self) -> Playback:
        return self._player.playback

    @property
    def position(self) -> float | None:
        return self._player.position

    def play(self, source: Source) -> None:
        self._player.play(source)
        pause_desktop(self._media)

    def resume(self) -> None:
        self._player.resume()
        pause_desktop(self._media)

    def stop(self) -> None:
        self._player.stop()

    def pause(self) -> None:
        self._player.pause()

    def louder(self) -> Playback:
        return self._player.louder()

    def quieter(self) -> Playback:
        return self._player.quieter()

    def seek(self, seconds: float) -> float | None:
        return self._player.seek(seconds)
