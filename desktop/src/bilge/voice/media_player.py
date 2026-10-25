"""Bilge's own player for radio stations and podcast episodes: a background thread decodes the stream with PyAV and
feeds the output device under Bilge's voice, so a station is turned down (and an episode waits) while Bilge listens
or speaks, and the microphone's echo cancelling knows what the speaker plays."""

import logging
import threading
from collections.abc import Callable, Iterator
from dataclasses import replace
from typing import Protocol

import numpy as np

from bilge.core.language import AssistantLanguage
from bilge.core.media import playback_state as state
from bilge.core.media.playback_state import Playback, Source
from bilge.tools import web_fetch
from bilge.tools.player import PlaybackError
from bilge.voice.audio_io import BackgroundBuffer

log = logging.getLogger(__name__)
# Decoded audio kept ahead of the speaker: enough to ride out a slow segment, little enough to seek at once.
AHEAD_SECONDS = 3.0
START_TIMEOUT_SECONDS = 10.0
# A seek past the end lands this far before it, so the episode's last words still play.
END_MARGIN_SECONDS = 5.0
_WAIT = 0.05


class Sink(Protocol):
    sample_rate: int
    background: BackgroundBuffer


class Decoder(Protocol):
    @property
    def duration(self) -> float | None:
        """The stream's length in seconds, when it says (an episode's file does; a station doesn't)."""
        ...

    def blocks(self) -> Iterator[tuple[np.ndarray, float]]:
        """Mono float32 at the sink's rate, each with the stream time where it ends."""
        ...

    def seek(self, seconds: float) -> None:
        """Called between blocks, on the thread reading them."""
        ...

    def close(self) -> None:
        """May be called from another thread, to end a read waiting on the network."""
        ...


Opener = Callable[[Source, int, threading.Event], Decoder]


class _Session:
    """One stream being decoded, from its opening until it ends or is stopped."""

    def __init__(self, source: Source, sink: Sink, opener: Opener, on_end: Callable[["_Session"], None]):
        self.source = source
        self._sink = sink
        self._opener = opener
        self._on_end = on_end
        self.stopped = threading.Event()
        self.ready = threading.Event()
        self.error: Exception | None = None
        self._decoder: Decoder | None = None
        self._seek_to: float | None = None
        self._lock = threading.Lock()
        self.until = 0.0
        self.duration: float | None = None
        self._thread = threading.Thread(target=self._run, name="bilge-player", daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self.stopped.set()
        with self._lock:
            decoder = self._decoder
        if decoder is not None:
            try:
                decoder.close()
            except Exception:  # noqa: BLE001 - closing a dead stream must not stop the next one
                log.debug("Closing the decoder failed", exc_info=True)
        if threading.current_thread() is not self._thread:
            self._thread.join(timeout=2)

    def seek(self, seconds: float) -> None:
        with self._lock:
            self._seek_to = seconds

    @property
    def position(self) -> float:
        """Where the speaker is: the decoded time less what still waits to be played."""
        queued = self._sink.background.queued / self._sink.sample_rate
        return max(0.0, self.until - queued)

    def _run(self) -> None:
        try:
            decoder = self._opener(self.source, self._sink.sample_rate, self.stopped)
            with self._lock:
                self._decoder = decoder
            self.duration = decoder.duration
            if self.stopped.is_set():
                decoder.close()
                return
            self._play(decoder)
        except Exception as error:  # noqa: BLE001 - whatever the network or decoder raised ends this stream only
            if not self.stopped.is_set():
                log.info("Playback of %s failed: %r", self.source.url, error)
                self.error = error
        finally:
            if not self.stopped.is_set():
                self._on_end(self)
            self.ready.set()

    def _play(self, decoder: Decoder) -> None:
        background = self._sink.background
        while True:
            for samples, until in decoder.blocks():
                seek_to = self._take_seek()
                if seek_to is not None:
                    self._jump(decoder, seek_to)
                    continue
                if self.stopped.is_set():
                    return
                background.add(samples)
                self.until = until
                self.ready.set()
                while background.queued > AHEAD_SECONDS * self._sink.sample_rate and not self.stopped.is_set():
                    if self._seek_to is not None:
                        break
                    self.stopped.wait(_WAIT)
            # Decoded to the end: wait for the speaker to finish what is queued, unless a seek in those last seconds
            # sends it back.
            while background.queued and self._seek_to is None and not self.stopped.is_set():
                self.stopped.wait(_WAIT)
            seek_to = self._take_seek()
            if seek_to is None or self.stopped.is_set():
                break
            self._jump(decoder, seek_to)
        decoder.close()

    def _take_seek(self) -> float | None:
        with self._lock:
            seek_to, self._seek_to = self._seek_to, None
        return seek_to

    def _jump(self, decoder: Decoder, seconds: float) -> None:
        decoder.seek(seconds)
        self._sink.background.clear()
        self.until = seconds


class MediaPlayer:
    def __init__(
        self,
        language: AssistantLanguage,
        sink: Sink | None = None,
        opener: Opener | None = None,
        start_timeout: float = START_TIMEOUT_SECONDS,
    ):
        """Without a sink (the text chat), the first stream opens an output of its own."""
        self._language = language
        self._sink = sink
        self._opener = opener or (lambda source, rate, stopped: open_decoder(source, rate, stopped, language))
        self._start_timeout = start_timeout
        self._lock = threading.RLock()
        self._playback = Playback()
        self._session: _Session | None = None

    def attach(self, sink: Sink) -> None:
        """The voice assistant's output device, once it exists."""
        with self._lock:
            self._sink = sink

    @property
    def playback(self) -> Playback:
        with self._lock:
            return self._playback

    @property
    def position(self) -> float | None:
        with self._lock:
            session = self._session
        return session.position if session is not None and self._playback.is_active else None

    def play(self, source: Source) -> None:
        """Starts the source and returns once its first audio is decoded; PlaybackError when it can't."""
        with self._lock:
            self._update(state.started(self._playback, source), restart=True)
            session = self._session
        self._wait_for(session)

    def stop(self) -> None:
        with self._lock:
            self._update(state.stopped(self._playback))

    def pause(self) -> None:
        with self._lock:
            self._update(state.paused(self._playback))

    def resume(self) -> None:
        with self._lock:
            before = self._playback
            self._update(state.resumed(before))
            session = self._session if state.restarts(before, self._playback) else None
        if session is not None:
            self._wait_for(session)

    def louder(self) -> Playback:
        with self._lock:
            self._update(state.louder(self._playback))
            return self._playback

    def quieter(self) -> Playback:
        with self._lock:
            self._update(state.quieter(self._playback))
            return self._playback

    def set_busy(self, on: bool) -> None:
        """Bilge started or finished listening or speaking."""
        with self._lock:
            if self._playback.assistant_busy != on:
                self._update(state.busy(self._playback, on))

    def seek(self, seconds: float) -> float | None:
        """Moves the episode by `seconds` (back when negative), within its length; the new position, or None for a
        live station."""
        with self._lock:
            session = self._session
            if session is None or not self._playback.is_active or self._playback.source.is_live:
                return None
            position = session.position
            target = max(0.0, position + seconds)
            if session.duration is not None:
                target = min(target, max(position, session.duration - END_MARGIN_SECONDS))
            session.seek(target)
            return target

    def _wait_for(self, session: _Session | None) -> None:
        if session is None:
            return
        started = session.ready.wait(self._start_timeout)
        if started and session.error is None:
            return
        with self._lock:
            if self._session is session:
                self._update(state.stopped(self._playback))
        error = session.error if started else web_fetch.WebFetchError(web_fetch.Reason.TOO_SLOW)
        raise PlaybackError(error if isinstance(error, web_fetch.WebFetchError) else None)

    def _update(self, after: Playback, restart: bool = False) -> None:
        """Called with the lock held: opens or lets go of the stream as the new state needs, then sets the level."""
        before = self._playback
        self._playback = after
        if restart or state.restarts(before, after):
            self._end_session()
            self._session = _Session(after.source, self._output(), self._opener, self._ended)
            self._session.start()
        elif state.disconnects(before, after):
            self._end_session()
        if self._sink is not None:
            self._sink.background.set_level(after.gain, after.holds)

    def _end_session(self) -> None:
        if self._session is not None:
            self._session.stop()
            self._session = None
        if self._sink is not None:
            self._sink.background.clear()

    def _ended(self, session: _Session) -> None:
        # Whoever holds the lock may be stopping this very session and waiting for its thread.
        while not self._lock.acquire(timeout=_WAIT):
            if session.stopped.is_set():
                return
        try:
            if self._session is session:
                self._session = None
                self._playback = replace(self._playback, state=state.State.STOPPED)
        finally:
            self._lock.release()

    def _output(self) -> Sink:
        if self._sink is None:
            self._sink = StandaloneOutput()
        return self._sink


class StandaloneOutput:
    """The speaker on its own, for when Bilge runs without its voice loop."""

    def __init__(self) -> None:
        import sounddevice as sd

        device = sd.default.device[1]
        self.sample_rate = int(sd.query_devices(device, "output")["default_samplerate"])
        self.background = BackgroundBuffer()

        def callback(outdata, frames, time, status):
            outdata[:] = self.background.take(frames)[:, None]

        self._stream = sd.OutputStream(samplerate=self.sample_rate, channels=1, dtype="float32", callback=callback)
        self._stream.start()


class PyAVDecoder:
    """Any stream FFmpeg reads, as mono float32 at the given rate."""

    def __init__(self, reader, sample_rate: int):
        import av

        self._av = av
        self._reader = reader
        self._rate = sample_rate
        self._container = av.open(reader, mode="r")
        if not self._container.streams.audio:
            self._container.close()
            raise ValueError("no audio stream")
        self._stream = self._container.streams.audio[0]
        self._resampler = self._new_resampler()
        self._sought = False
        length = self._container.duration
        self.duration = length / av.time_base if length and length > 0 else None

    def _new_resampler(self):
        return self._av.AudioResampler(format="flt", layout="mono", rate=self._rate)

    def blocks(self) -> Iterator[tuple[np.ndarray, float]]:
        while True:
            for frame in self._container.decode(self._stream):
                end = (frame.time or 0.0) + frame.samples / (frame.sample_rate or self._rate)
                for converted in self._resampler.resample(frame):
                    if self._sought:
                        break
                    yield converted.to_ndarray().reshape(-1).astype(np.float32, copy=False), end
                if self._sought:
                    break
            if not self._sought:
                return
            # Decoding starts over from the new place.
            self._sought = False

    def seek(self, seconds: float) -> None:
        self._container.seek(int(seconds * self._av.time_base), backward=True, any_frame=False)
        self._resampler = self._new_resampler()
        self._sought = True

    def close(self) -> None:
        self._reader.close()


def open_decoder(source: Source, sample_rate: int, stopped: threading.Event, language: AssistantLanguage) -> Decoder:
    from bilge.tools import web_stream

    if source.is_live:
        reader = web_stream.open_live(source.url, language, stopped, source.is_playlist)
    else:
        reader = web_stream.RangeReader(source.url, language)
    try:
        return PyAVDecoder(reader, sample_rate)
    except Exception:
        reader.close()
        raise
