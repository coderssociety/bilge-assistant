"""Music and video players through MPRIS, the D-Bus interface Spotify, Rhythmbox, VLC, browsers and others share."""

from bilge.desktop.base import AppEntry, Apps, MediaCommand, NowPlaying, RepeatMode
from bilge.desktop.linux.dbus import Bus
from bilge.desktop.music import is_spotify
from bilge.desktop.process import DesktopError, NotPossibleHere, Runner

_PREFIX = "org.mpris.MediaPlayer2."
_PATH = "/org/mpris/MediaPlayer2"
_ROOT = "org.mpris.MediaPlayer2"
_PLAYER = "org.mpris.MediaPlayer2.Player"
_METHODS = {
    MediaCommand.PLAY: "Play",
    MediaCommand.PAUSE: "Pause",
    MediaCommand.TOGGLE: "PlayPause",
    MediaCommand.NEXT: "Next",
    MediaCommand.PREVIOUS: "Previous",
}
# The player the user most likely means: the one playing, then one paused mid-track.
_PREFERENCE = {"Playing": 0, "Paused": 1}
_PROPERTIES = "org.freedesktop.DBus.Properties"
_LOOP_STATUS = {RepeatMode.OFF: "None", RepeatMode.TRACK: "Track", RepeatMode.ALL: "Playlist"}
_MICROSECONDS = 1_000_000


class NoPlayer(DesktopError):
    pass


class MprisMedia:
    def __init__(self, bus: Bus):
        self._bus = bus

    def now_playing(self) -> NowPlaying | None:
        player = self._choose()
        if player is None:
            return None
        name, status = player
        metadata = self._optional(name, _PLAYER, "Metadata") or {}
        title = _text(metadata.get("xesam:title"))
        artists = _value(metadata.get("xesam:artist"))
        artist = ", ".join(artists) if isinstance(artists, list) else _text(metadata.get("xesam:artist"))
        return NowPlaying(self._identity(name), status == "Playing", title, artist)

    def send(self, command: MediaCommand) -> str:
        name = self._player()
        self._bus.call(name, _PATH, _PLAYER, _METHODS[command])
        return self._identity(name)

    def seek(self, seconds: float) -> str:
        name = self._player()
        if self._optional(name, _PLAYER, "CanSeek") is False:
            raise NotPossibleHere(f"{name} can't seek")
        self._bus.call(name, _PATH, _PLAYER, "Seek", "x", round(seconds * _MICROSECONDS))
        return self._identity(name)

    def restart_track(self) -> str:
        name = self._player()
        if self._optional(name, _PLAYER, "CanSeek") is False:
            raise NotPossibleHere(f"{name} can't seek")
        metadata = self._optional(name, _PLAYER, "Metadata") or {}
        track = _value(metadata.get("mpris:trackid"))
        if track:
            self._bus.call(name, _PATH, _PLAYER, "SetPosition", "ox", str(track), 0)
        else:
            # Without a track id, seeking back past the start lands on it.
            position = int(self._optional(name, _PLAYER, "Position") or 0)
            self._bus.call(name, _PATH, _PLAYER, "Seek", "x", -position)
        return self._identity(name)

    def set_shuffle(self, on: bool) -> str:
        return self._set_optional("Shuffle", ("b", on))

    def set_repeat(self, mode: RepeatMode) -> str:
        return self._set_optional("LoopStatus", ("s", _LOOP_STATUS[mode]))

    def _set_optional(self, prop: str, value: tuple[str, object]) -> str:
        """Shuffle and LoopStatus are optional in MPRIS; a player without them can't do it."""
        name = self._player()
        if self._optional(name, _PLAYER, prop) is None:
            raise NotPossibleHere(f"{name} has no {prop}")
        self._bus.call(name, _PATH, _PROPERTIES, "Set", "ssv", _PLAYER, prop, value)
        return self._identity(name)

    def _player(self) -> str:
        player = self._choose()
        if player is None:
            raise NoPlayer("No MPRIS player is running")
        return player[0]

    def _choose(self) -> tuple[str, str] | None:
        players = [name for name in self._bus.names() if name.startswith(_PREFIX)]
        if not players:
            return None
        statuses = [(name, str(self._optional(name, _PLAYER, "PlaybackStatus") or "")) for name in players]
        return min(statuses, key=lambda item: _PREFERENCE.get(item[1], 2))

    def _identity(self, name: str) -> str:
        identity = self._optional(name, _ROOT, "Identity")
        if identity:
            return str(identity)
        # "org.mpris.MediaPlayer2.spotify" or "…chromium.instance1234".
        return name.removeprefix(_PREFIX).split(".")[0].capitalize()

    def _optional(self, name: str, interface: str, prop: str):
        """Players implement the optional properties unevenly; a missing one is not an error."""
        try:
            return self._bus.get(name, _PATH, interface, prop)
        except DesktopError:
            return None


def _value(variant):
    """Metadata values are variants, (signature, value)."""
    if isinstance(variant, tuple) and len(variant) == 2:
        return variant[1]
    return variant


def _text(variant) -> str:
    value = _value(variant)
    return str(value) if value else ""


# Players that take MPRIS commands, by a part of their desktop file id, in the order they are preferred.
_MPRIS_PLAYERS = (
    "spotify", "rhythmbox", "elisa", "lollypop", "strawberry", "clementine", "org.gnome.music", "amarok", "audacious",
    "quodlibet", "deadbeef", "cantata", "tauon", "g4music", "amberol", "decibels", "vlc", "celluloid",
)  # fmt: skip
# The app the user chose for music files, which is the player they use.
_MUSIC_TYPE = "audio/mpeg"


def installed_players(apps: Apps, runner: Runner) -> list[AppEntry]:
    """Spotify first, since "müzik çal" with it installed means it; then the app chosen for music files; then any
    other MPRIS player."""
    entries = apps.installed()
    by_id = {entry.id: entry for entry in entries}
    known = [entry for entry in entries if any(part in entry.id.lower() for part in _MPRIS_PLAYERS)]
    known.sort(key=lambda entry: next(i for i, part in enumerate(_MPRIS_PLAYERS) if part in entry.id.lower()))
    chosen = by_id.get(_default_music_app(runner) or "")
    ordered = [entry for entry in known if is_spotify(entry)] + ([chosen] if chosen else []) + known
    return list({entry.id: entry for entry in ordered}.values())


def _default_music_app(runner: Runner) -> str | None:
    if not runner.has("xdg-mime"):
        return None
    try:
        done = runner.run(["xdg-mime", "query", "default", _MUSIC_TYPE], timeout=5)
    except DesktopError:
        return None
    return (done.stdout.strip() or None) if done.ok else None
