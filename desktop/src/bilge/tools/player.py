"""What the radio, podcast and media tools need from Bilge's own player, and how a failed start is said."""

from typing import Protocol

from bilge.core.language import AssistantLanguage
from bilge.core.media.playback_state import Playback, Source
from bilge.tools import web_fetch


class PlaybackError(Exception):
    """The stream didn't start: it couldn't be reached (`fetch` holds why) or its audio couldn't be decoded."""

    def __init__(self, fetch: web_fetch.WebFetchError | None = None):
        super().__init__(fetch.reason.value if fetch else "decode")
        self.fetch = fetch


class Player(Protocol):
    @property
    def playback(self) -> Playback: ...

    @property
    def position(self) -> float | None: ...

    def play(self, source: Source) -> None:
        """Returns once the first audio is decoded; PlaybackError when the stream can't start."""
        ...

    def stop(self) -> None: ...

    def pause(self) -> None: ...

    def resume(self) -> None: ...

    def louder(self) -> Playback: ...

    def quieter(self) -> Playback: ...

    def seek(self, seconds: float) -> float | None:
        """The new position in the episode, or None for a live station."""
        ...


def failure(error: PlaybackError, language: AssistantLanguage) -> str:
    if error.fetch is not None:
        return web_fetch.describe(error.fetch, language)
    if language is AssistantLanguage.ENGLISH:
        return "Its audio is in a format I can't play."
    return "Yayının ses biçimini çalamıyorum."
