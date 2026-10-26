"""What Bilge's own player is doing (a radio station or a podcast episode), as plain state: playing, paused or
stopped, how loud, and how it makes way while Bilge listens or speaks. A live station is turned down; an episode
waits, so nothing in it is missed."""

from dataclasses import dataclass, replace
from enum import StrEnum

# How loud a station stays while Bilge listens or speaks, against its own level.
DUCKED = 0.2
VOLUME_STEP = 0.2
MIN_VOLUME = 0.2
MAX_VOLUME = 1.0


class Kind(StrEnum):
    RADIO = "radio"
    EPISODE = "episode"


class State(StrEnum):
    STOPPED = "stopped"
    PLAYING = "playing"
    PAUSED = "paused"


@dataclass(frozen=True)
class Source:
    kind: Kind
    # The station's or show's name as Bilge says it.
    name: str
    url: str
    # A playlist of segments (HLS) rather than one stream.
    is_playlist: bool = False
    # The episode's title, written by whoever made the show.
    title: str = ""

    @property
    def is_live(self) -> bool:
        return self.kind is Kind.RADIO


@dataclass(frozen=True)
class Playback:
    source: Source | None = None
    state: State = State.STOPPED
    volume: float = MAX_VOLUME
    # Bilge is listening to a request or answering one.
    assistant_busy: bool = False

    @property
    def is_playing(self) -> bool:
        return self.state is State.PLAYING

    @property
    def is_active(self) -> bool:
        """Something is loaded: playing, or paused and waiting to go on."""
        return self.state is not State.STOPPED and self.source is not None

    @property
    def holds(self) -> bool:
        """The output keeps its place without playing: a paused episode, or one waiting for Bilge to finish."""
        if self.source is None or self.state is State.STOPPED:
            return False
        return self.state is State.PAUSED or (self.assistant_busy and not self.source.is_live)

    @property
    def gain(self) -> float:
        if not self.is_playing or self.holds:
            return 0.0
        return self.volume * (DUCKED if self.assistant_busy else 1.0)

    @property
    def connected(self) -> bool:
        """A stream should be open: a live station is let go while paused, since it can't wait anyway."""
        if not self.is_active or self.source is None:
            return False
        return self.state is State.PLAYING or not self.source.is_live


def started(playback: Playback, source: Source) -> Playback:
    return replace(playback, source=source, state=State.PLAYING)


def stopped(playback: Playback) -> Playback:
    """The source is kept, so "radyoyu aç" can go back to it."""
    return replace(playback, state=State.STOPPED)


def paused(playback: Playback) -> Playback:
    return replace(playback, state=State.PAUSED) if playback.is_active else playback


def resumed(playback: Playback) -> Playback:
    return replace(playback, state=State.PLAYING) if playback.state is State.PAUSED else playback


def busy(playback: Playback, on: bool) -> Playback:
    return replace(playback, assistant_busy=on)


def louder(playback: Playback) -> Playback:
    return replace(playback, volume=round(min(MAX_VOLUME, playback.volume + VOLUME_STEP), 2))


def quieter(playback: Playback) -> Playback:
    return replace(playback, volume=round(max(MIN_VOLUME, playback.volume - VOLUME_STEP), 2))


def restarts(before: Playback, after: Playback) -> bool:
    """The stream must be opened (again): a new source, or a live station coming back from a pause or a stop."""
    if not after.connected:
        return False
    return not before.connected or before.source != after.source


def disconnects(before: Playback, after: Playback) -> bool:
    return before.connected and not after.connected
