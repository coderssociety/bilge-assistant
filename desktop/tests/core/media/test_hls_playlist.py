import pytest

from bilge.core.media import hls_playlist

MASTER = """#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.5"
low/playlist.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,CODECS="avc1.4d401f,mp4a.40.2",RESOLUTION=1280x720
video/playlist.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS="mp4a.40.2"
https://cdn.example/high/playlist.m3u8
"""

LIVE = """#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:6
#EXT-X-MEDIA-SEQUENCE:37287
#EXTINF:5.99,
l_37287.ts?session=1
#EXTINF:5.99,
l_37288.ts?session=1
"""


def test_audio_variants_come_first_best_first():
    playlist = hls_playlist.parse(MASTER, "https://radio.example/powerfm/master.m3u8")
    assert playlist.variants == (
        "https://cdn.example/high/playlist.m3u8",
        "https://radio.example/powerfm/low/playlist.m3u8",
        "https://radio.example/powerfm/video/playlist.m3u8",
    )
    assert playlist.segments == ()


def test_live_segments_are_numbered_from_the_media_sequence():
    playlist = hls_playlist.parse(LIVE, "https://radio.example/powerfm/chunks.m3u8")
    assert playlist.segments == (
        hls_playlist.Segment(37287, "https://radio.example/powerfm/l_37287.ts?session=1"),
        hls_playlist.Segment(37288, "https://radio.example/powerfm/l_37288.ts?session=1"),
    )
    assert playlist.target_seconds == 6.0 and not playlist.ended


def test_a_finished_list_with_an_init_section():
    text = '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:4,\nseg1.m4s\n#EXT-X-ENDLIST\n'
    playlist = hls_playlist.parse(text, "https://vod.example/a/index.m3u8")
    assert playlist.ended and playlist.init == "https://vod.example/a/init.mp4"


def test_encrypted_segments_are_refused():
    with pytest.raises(hls_playlist.UnsupportedPlaylist):
        hls_playlist.parse('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="k"\n#EXTINF:6,\na.ts\n', "https://x.example/")


def test_a_playlist_is_told_from_audio_by_its_first_line():
    assert hls_playlist.is_playlist(b"\xef\xbb\xbf#EXTM3U\n")
    assert not hls_playlist.is_playlist(b"ID3\x04\x00")
