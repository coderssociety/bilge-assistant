import pytest

from bilge.core.media import youtube_video
from bilge.core.media.youtube_video import Track

BASE = "https://www.youtube.com/api/timedtext?v=4gtWE9OOagw&ei=x&caps=asr&opi=1&xoaf=5&hl=tr&expire=1&key=yt8"

PLAYER = {
    "playabilityStatus": {"status": "OK"},
    "videoDetails": {"videoId": "4gtWE9OOagw", "title": "Röportaj", "lengthSeconds": "1520"},
    "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [
        {"baseUrl": BASE + "&kind=asr&lang=tr&fmt=srv3", "languageCode": "tr", "kind": "asr"},
        {"baseUrl": BASE + "&lang=en&fmt=srv3", "languageCode": "en"},
        {"baseUrl": "https://evil.example/timedtext?lang=de", "languageCode": "de"},
        {"baseUrl": "http://www.youtube.com/api/timedtext?lang=fr", "languageCode": "fr"},
        "junk",
    ]}},
}  # fmt: skip

SIMPLE = (
    b'<?xml version="1.0" encoding="utf-8" ?><transcript>'
    b'<text start="2.97" dur="6.43">[M\xc3\xbczik]</text>'
    b'<text start="6.72" dur="5.8">Merhaba sevgili izleyiciler</text>'
    b'<text start="9.4" dur="5.4">it&amp;#39;s   fine\n</text></transcript>'
)
TIMED = (
    b'<?xml version="1.0" encoding="utf-8" ?><timedtext format="3"><body>'
    b'<p t="2970" d="6430" w="1">[M\xc3\xbczik]</p><p t="6710" d="2690" w="1" a="1">\n</p>'
    b'<p t="6720" d="5799" w="1"><s ac="0">Merhaba</s><s t="440" ac="0"> sevgili</s></p></body></timedtext>'
)


@pytest.mark.parametrize(
    "text",
    [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "şuna bak: https://youtu.be/dQw4w9WgXcQ?si=abc",
        "https://m.youtube.com/watch?feature=share&v=dQw4w9WgXcQ&t=30",
        "youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ?feature=x",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RD",
    ],
)
def test_the_video_id_is_found_in_every_kind_of_link(text):
    assert youtube_video.video_id(text) == "dQw4w9WgXcQ"


@pytest.mark.parametrize(
    "text", ["", "https://vimeo.com/123", "https://www.youtube.com/watch?v=short", "https://youtube.com/@kanal"]
)
def test_no_id_without_a_youtube_video_link(text):
    assert youtube_video.video_id(text) is None


def test_tracks_come_only_from_youtube_over_https_without_the_format():
    video = youtube_video.video(PLAYER)
    assert video.title == "Röportaj" and video.playable
    assert [(t.language, t.automatic) for t in video.tracks] == [("tr", True), ("en", False)]
    assert "fmt=" not in video.tracks[0].url and "lang=tr" in video.tracks[0].url


def test_a_broken_answer_is_an_unplayable_video_without_captions():
    assert youtube_video.video({"captions": "x", "playabilityStatus": []}) == youtube_video.Video("", False, ())
    assert youtube_video.video(None) == youtube_video.Video("", False, ())


def track(language, automatic=False):
    return Track(language, automatic, f"https://www.youtube.com/api/timedtext?lang={language}")


def test_written_turkish_wins_then_generated_turkish():
    assert youtube_video.choose((track("en"), track("tr", True), track("tr")), "tr") == track("tr")
    assert youtube_video.choose((track("en"), track("tr", True)), "tr") == track("tr", True)


def test_without_turkish_the_language_the_video_speaks():
    tracks = (track("en"), track("de-DE"), track("de", True), track("ja"))
    assert youtube_video.choose(tracks, "tr") == track("de-DE")
    assert youtube_video.choose((track("ja"), track("en")), "tr") == track("en")
    assert youtube_video.choose((track("ja"),), "tr") == track("ja")
    assert youtube_video.choose((), "tr") is None


def test_both_caption_formats_read_as_plain_text():
    assert youtube_video.transcript(SIMPLE) == "[Müzik] Merhaba sevgili izleyiciler it's fine"
    assert youtube_video.transcript(TIMED) == "[Müzik] Merhaba sevgili"
    assert youtube_video.transcript(b"") == ""
    assert youtube_video.transcript(b"<transcript><text>yar") == ""
