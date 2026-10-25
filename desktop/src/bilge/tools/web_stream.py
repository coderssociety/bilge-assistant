"""Radio streams and podcast episodes as file-like objects for the decoder, fetched through web_fetch so they get
the same address checks as everything else Bilge fetches. A station is one endless answer or an HLS playlist whose
segments are fetched one after another; an episode is read with ranges, so it can be sought."""

import io
import logging
import threading
from collections.abc import Callable, Iterator

from bilge.core.language import AssistantLanguage
from bilge.core.media import hls_playlist
from bilge.tools import web_fetch

log = logging.getLogger(__name__)
CHUNK = 32 * 1024
PLAYLIST_BYTES = 512 * 1024
SEGMENT_BYTES = 8 * 1024 * 1024
# Segments a live playlist is joined at from its end: close to live, with a little in hand.
LIVE_EDGE_SEGMENTS = 3
MAX_VARIANT_HOPS = 3


class PipeReader(io.RawIOBase):
    """Reads through an iterator of byte chunks; not seekable, as a live stream isn't."""

    def __init__(self, chunks: Iterator[bytes], on_close: Callable[[], None] = lambda: None):
        super().__init__()
        self._chunks = chunks
        self._pending = b""
        self._on_close = on_close

    def readable(self) -> bool:
        return True

    def read(self, size: int = -1) -> bytes:
        while not self.closed and (size < 0 or len(self._pending) < size):
            chunk = next(self._chunks, None)
            if chunk is None:
                break
            self._pending += chunk
        if size < 0:
            size = len(self._pending)
        out, self._pending = self._pending[:size], self._pending[size:]
        return out

    def close(self) -> None:
        if not self.closed:
            self._on_close()
        super().close()


class RangeReader(io.RawIOBase):
    """An episode read from an offset with HTTP ranges, opened again wherever the decoder seeks, and after a
    dropped connection (a long pause) at the place it stopped. Read and sought from one thread; closed from any."""

    def __init__(self, url: str, language: AssistantLanguage, opener=web_fetch.open_stream):
        super().__init__()
        self._url = url
        self._language = language
        self._open = opener
        self._position = 0
        self._stream: web_fetch.Stream | None = None
        self._length: int | None = None
        self._lock = threading.Lock()
        self._closing = False
        self._ensure()

    def readable(self) -> bool:
        return True

    def seekable(self) -> bool:
        return self._length is not None

    def tell(self) -> int:
        return self._position

    @property
    def length(self) -> int | None:
        return self._length

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        with self._lock:
            base = {io.SEEK_SET: 0, io.SEEK_CUR: self._position, io.SEEK_END: self._length or 0}[whence]
            target = max(0, base + offset)
            if target != self._position:
                self._drop()
                self._position = target
            return self._position

    def read(self, size: int = -1) -> bytes:
        if self._length is not None and self._position >= self._length:
            return b""
        for attempt in range(2):
            try:
                stream = self._ensure()
                data = stream.read(CHUNK if size < 0 else size)
            except web_fetch.WebFetchError:
                if attempt or self._closing:
                    raise
                with self._lock:
                    self._drop()
                continue
            if not data and not attempt and self._length is not None and self._position < self._length:
                # The server closed early; the rest is asked for again.
                with self._lock:
                    self._drop()
                continue
            with self._lock:
                self._position += len(data)
            return data
        return b""

    def close(self) -> None:
        """Also from another thread, to end a read that waits on the network."""
        self._closing = True
        with self._lock:
            self._drop()
        super().close()

    def _ensure(self) -> web_fetch.Stream:
        with self._lock:
            if self._closing:
                raise web_fetch.WebFetchError(web_fetch.Reason.CONNECT)
            if self._stream is not None:
                return self._stream
            position = self._position
        # Opened outside the lock, so closing from another thread never waits on the network.
        stream = self._open(self._url, self._language, position)
        if position and not stream.ranged:
            stream.close()
            raise web_fetch.WebFetchError(web_fetch.Reason.UNEXPECTED)
        with self._lock:
            if self._closing:
                stream.close()
                raise web_fetch.WebFetchError(web_fetch.Reason.CONNECT)
            self._stream = stream
            self._length = self._length or stream.length
            return stream

    def _drop(self) -> None:
        if self._stream is not None:
            self._stream.close()
            self._stream = None


def open_live(url: str, language: AssistantLanguage, stopped: threading.Event, is_playlist: bool) -> PipeReader:
    """A station: one endless answer, or an HLS playlist (also when a plain-looking address turns out to be one)."""
    if is_playlist:
        return PipeReader(_segments(url, language, stopped))
    stream = web_fetch.open_stream(url, language)
    first = stream.read(CHUNK)
    if "mpegurl" in stream.content_type.lower() or hls_playlist.is_playlist(first):
        stream.close()
        return PipeReader(_segments(url, language, stopped))
    return PipeReader(_chunks(stream, first), on_close=stream.close)


def _chunks(stream: web_fetch.Stream, first: bytes) -> Iterator[bytes]:
    yield first
    while chunk := stream.read(CHUNK):
        yield chunk


def _playlist(url: str, language: AssistantLanguage) -> hls_playlist.Playlist:
    response = web_fetch.get(url, language, max_bytes=PLAYLIST_BYTES)
    if response.status != 200:
        raise web_fetch.WebFetchError(web_fetch.Reason.STATUS, response.status)
    return hls_playlist.parse(response.text(), response.url)


def _segment(url: str, language: AssistantLanguage) -> bytes:
    response = web_fetch.get(url, language, max_bytes=SEGMENT_BYTES)
    if response.status != 200:
        raise web_fetch.WebFetchError(web_fetch.Reason.STATUS, response.status)
    return response.body


def _segments(url: str, language: AssistantLanguage, stopped: threading.Event) -> Iterator[bytes]:
    """Each new segment's bytes in order, fetching the playlist again as a live one grows."""
    playlist = _playlist(url, language)
    for _ in range(MAX_VARIANT_HOPS):
        if not playlist.variants:
            break
        url = playlist.variants[0]
        playlist = _playlist(url, language)
    if playlist.init:
        yield _segment(playlist.init, language)
    following = None if playlist.ended else _live_start(playlist)
    while not stopped.is_set():
        for segment in playlist.segments:
            if following is not None and segment.sequence < following:
                continue
            if stopped.is_set():
                return
            yield _segment(segment.url, language)
            following = segment.sequence + 1
        if playlist.ended:
            return
        if stopped.wait(max(1.0, playlist.target_seconds / 2)) or stopped.is_set():
            return
        playlist = _playlist(url, language)
        if playlist.segments and following is not None and playlist.segments[-1].sequence < following - 1:
            # The server started its numbering again.
            following = playlist.segments[0].sequence


def _live_start(playlist: hls_playlist.Playlist) -> int | None:
    if not playlist.segments:
        return None
    return playlist.segments[max(0, len(playlist.segments) - LIVE_EDGE_SEGMENTS)].sequence
