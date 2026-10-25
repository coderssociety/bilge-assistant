import io
import threading

import pytest

from bilge.core.language import AssistantLanguage
from bilge.tools import web_fetch, web_stream

TR = AssistantLanguage.TURKISH
EPISODE = bytes(range(256)) * 4


class FakeStream:
    def __init__(self, data, start, ranged=True, fail_after=None):
        self._data = data[start:] if ranged else data
        self.ranged = ranged and start > 0
        self.length = len(data)
        self.content_type = "audio/mpeg"
        self._fail_after = fail_after
        self._read = 0
        self.closed = False

    def read(self, size):
        if self._fail_after is not None and self._read >= self._fail_after:
            raise web_fetch.WebFetchError(web_fetch.Reason.CONNECT)
        chunk, self._data = self._data[:size], self._data[size:]
        self._read += len(chunk)
        return chunk

    def close(self):
        self.closed = True


class Opener:
    def __init__(self, **options):
        self.options = options
        self.starts = []

    def __call__(self, url, language, start):
        self.starts.append(start)
        options = self.options if len(self.starts) == 1 else {}
        return FakeStream(EPISODE, start, **options)


def test_an_episode_is_read_and_sought_with_ranges():
    opener = Opener()
    reader = web_stream.RangeReader("https://cdn.example/1.mp3", TR, opener)
    assert reader.seekable() and reader.length == len(EPISODE)
    assert reader.read(4) == bytes([0, 1, 2, 3])
    reader.seek(512)
    assert reader.read(2) == bytes([0, 1]) and reader.tell() == 514
    reader.seek(-1, io.SEEK_END)
    assert reader.read(10) == bytes([255]) and reader.read(10) == b""
    assert opener.starts == [0, 512, len(EPISODE) - 1]


def test_a_dropped_connection_is_opened_again_where_it_stopped():
    opener = Opener(fail_after=100)
    reader = web_stream.RangeReader("https://cdn.example/1.mp3", TR, opener)
    assert len(reader.read(100)) == 100
    assert reader.read(1) == bytes([100])
    assert opener.starts == [0, 100]


def test_a_server_that_ignores_the_range_is_not_read_from_the_wrong_place():
    reader = web_stream.RangeReader("https://cdn.example/1.mp3", TR, lambda u, lang, s: FakeStream(EPISODE, s, False))
    reader.seek(10)
    with pytest.raises(web_fetch.WebFetchError):
        reader.read(1)


def test_closing_from_another_thread_ends_the_reading():
    reader = web_stream.RangeReader("https://cdn.example/1.mp3", TR, Opener())
    reader.close()
    with pytest.raises((web_fetch.WebFetchError, ValueError)):
        reader.read(1)


def test_a_pipe_reads_across_chunks_and_tells_the_stream_when_closed():
    closed = []
    pipe = web_stream.PipeReader(iter([b"ab", b"cde", b"f"]), on_close=lambda: closed.append(True))
    assert pipe.read(4) == b"abcd" and pipe.read(10) == b"ef" and pipe.read(1) == b""
    pipe.close()
    assert closed == [True] and not pipe.seekable()


def media_playlist(first, last):
    segments = "".join(f"#EXTINF:2,\ns{n}.ts\n" for n in range(first, last + 1))
    return f"#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:{first}\n{segments}"


def test_a_live_playlist_joins_near_its_end_and_follows_new_segments(monkeypatch):
    stopped = threading.Event()
    fetched = []
    playlists = iter([
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS="mp4a.40.2"\nchunks.m3u8\n',
        media_playlist(10, 14),
        media_playlist(12, 16),
    ])  # fmt: skip

    def get(url, language=TR, max_bytes=0, user_agent=""):
        if url.endswith(".m3u8"):
            return web_fetch.Response(url, 200, "application/vnd.apple.mpegurl", next(playlists).encode())
        fetched.append(url.rsplit("/", 1)[1])
        if url.endswith("s16.ts"):
            stopped.set()
        return web_fetch.Response(url, 200, "video/mp2t", url.encode())

    monkeypatch.setattr(web_fetch, "get", get)
    monkeypatch.setattr(stopped, "wait", lambda seconds: None)
    chunks = list(web_stream._segments("https://radio.example/powerfm/master.m3u8", TR, stopped))
    assert fetched == ["s12.ts", "s13.ts", "s14.ts", "s15.ts", "s16.ts"]
    assert chunks[0] == b"https://radio.example/powerfm/s12.ts"


def test_a_finished_playlist_is_played_from_its_start_to_its_end(monkeypatch):
    text = "#EXTM3U\n#EXTINF:4,\na.aac\n#EXTINF:4,\nb.aac\n#EXT-X-ENDLIST\n"

    def get(url, language=TR, max_bytes=0, user_agent=""):
        body = text.encode() if url.endswith(".m3u8") else url[-5:].encode()
        return web_fetch.Response(url, 200, "", body)

    monkeypatch.setattr(web_fetch, "get", get)
    assert list(web_stream._segments("https://vod.example/x.m3u8", TR, threading.Event())) == [b"a.aac", b"b.aac"]


def test_a_plain_address_that_turns_out_to_be_a_playlist_is_followed(monkeypatch):
    class Answer:
        content_type = "audio/x-mpegurl"

        def read(self, size):
            return b"#EXTM3U\n"

        def close(self):
            pass

    monkeypatch.setattr(web_fetch, "open_stream", lambda url, language: Answer())
    followed = []
    monkeypatch.setattr(web_stream, "_segments", lambda url, language, stopped: followed.append(url) or iter([b"x"]))
    reader = web_stream.open_live("https://radio.example/listen", TR, threading.Event(), is_playlist=False)
    assert reader.read(1) == b"x" and followed == ["https://radio.example/listen"]
