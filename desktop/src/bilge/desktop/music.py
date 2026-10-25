"""Starting music when no player is open, and playing what the user names ("Tarkan çal"). The platforms only say
which players are installed; starting one and waiting for it to take commands is the same everywhere."""

import logging
import time
from collections.abc import Callable
from urllib.parse import quote, quote_plus

from bilge.desktop.base import AppEntry, Apps, Media, MediaCommand, Opener, PlayerStart
from bilge.desktop.process import DesktopError

log = logging.getLogger(__name__)

# A player needs a few seconds after launch before it answers media commands.
PLAYER_WAIT_SECONDS = 10.0
_POLL_SECONDS = 0.5
WEB_MUSIC = "YouTube Music"
_WEB_SEARCH = "https://music.youtube.com/search?q={}"
_SPOTIFY_SEARCH = "spotify:search:{}"


def is_spotify(app: AppEntry) -> bool:
    return "spotify" in app.id.lower() or app.display_name.lower() == "spotify"


class MusicLauncher:
    def __init__(
        self,
        apps: Apps,
        opener: Opener,
        media: Media,
        players: Callable[[], list[AppEntry]],
        sleep: Callable[[float], None] = time.sleep,
        wait_seconds: float = PLAYER_WAIT_SECONDS,
    ):
        """`players` lists the installed players, the one to start first."""
        self._apps = apps
        self._opener = opener
        self._media = media
        self._players = players
        self._sleep = sleep
        self._wait_seconds = wait_seconds

    def start_player(self) -> PlayerStart | None:
        players = self._players()
        if not players:
            return None
        player = players[0]
        self._apps.launch(player)
        if not self._wait_for_player():
            return PlayerStart(player.display_name, playing=False)
        try:
            self._media.send(MediaCommand.PLAY)
        except DesktopError as error:
            log.info("%s started but would not play: %s", player.display_name, error)
            return PlayerStart(player.display_name, playing=False)
        return PlayerStart(player.display_name, playing=True)

    def play_search(self, query: str) -> str:
        spotify = next((app for app in self._players() if is_spotify(app)), None)
        if spotify is not None:
            self._opener.open(_SPOTIFY_SEARCH.format(quote(query, safe="")))
            return spotify.display_name
        self._opener.open(_WEB_SEARCH.format(quote_plus(query)))
        return WEB_MUSIC

    def _wait_for_player(self) -> bool:
        waited = 0.0
        while waited < self._wait_seconds:
            self._sleep(_POLL_SECONDS)
            waited += _POLL_SECONDS
            try:
                if self._media.now_playing() is not None:
                    return True
            except DesktopError:
                continue
        return False
