from bilge.core.media import playback_state as state
from bilge.core.media.playback_state import Playback, Source


class FakePlayer:
    """Bilge's player as the tools see it, keeping the state machine but playing nothing."""

    def __init__(self, error=None, position=12.0, duration=None):
        self.playback = Playback()
        self.error = error
        self.position = position
        self.duration = duration
        self.played: list[Source] = []
        self.sought: list[float] = []
        self.resumed = 0

    def play(self, source):
        if self.error is not None:
            raise self.error
        self.played.append(source)
        self.playback = state.started(self.playback, source)

    def stop(self):
        self.playback = state.stopped(self.playback)

    def pause(self):
        self.playback = state.paused(self.playback)

    def resume(self):
        self.resumed += 1
        self.playback = state.resumed(self.playback)

    def louder(self):
        self.playback = state.louder(self.playback)
        return self.playback

    def quieter(self):
        self.playback = state.quieter(self.playback)
        return self.playback

    def seek(self, seconds):
        if self.playback.source is None or self.playback.source.is_live:
            return None
        self.sought.append(seconds)
        target = max(0.0, self.position + seconds)
        return min(target, self.duration) if self.duration is not None else target
