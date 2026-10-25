from datetime import datetime

import pytest

from bilge.core.language import AssistantLanguage
from bilge.tools import web_fetch
from bilge.tools.base import ToolError
from bilge.tools.builtin import youtube
from bilge.tools.reading import TextReading

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
CAPTIONS = "https://www.youtube.com/api/timedtext?v=4gtWE9OOagw&lang=tr&kind=asr"
PLAYER = {
    "playabilityStatus": {"status": "OK"},
    "videoDetails": {"title": "Barış Özcan ile Röportaj"},
    "captions": {"playerCaptionsTracklistRenderer": {"captionTracks": [
        {"baseUrl": CAPTIONS + "&fmt=srv3", "languageCode": "tr", "kind": "asr"}]}},
}  # fmt: skip
TRANSCRIPT = (
    b'<?xml version="1.0" encoding="utf-8" ?><transcript><text start="2.97" dur="6.43">[M\xc3\xbczik]</text>'
    b'<text start="6.72" dur="5.8">Merhaba sevgili izleyiciler</text></transcript>'
)


def fake_youtube(monkeypatch, answers, captions=TRANSCRIPT):
    """`answers`: the player's answer for each client in turn (a dict, or an error to raise)."""
    sent = []

    def post_json(url, payload, language=TR, user_agent=""):
        sent.append(payload)
        answer = answers[len(sent) - 1]
        if isinstance(answer, Exception):
            raise answer
        return answer

    def get(url, language=TR, max_bytes=0, user_agent=""):
        sent.append(url)
        return web_fetch.Response(url, 200, "text/xml", captions)

    monkeypatch.setattr(web_fetch, "post_json", post_json)
    monkeypatch.setattr(web_fetch, "get", get)
    return sent


def tool(pasted=None, language=TR, reading=None):
    return youtube.summarize_video_tool(language, reading or TextReading(language), pasted)


def test_the_captions_of_the_video_on_the_clipboard_are_read(monkeypatch):
    sent = fake_youtube(monkeypatch, [PLAYER])
    looked = []

    def pasted():
        for text in ("bak: https://youtu.be/4gtWE9OOagw?si=x", "seçili metin"):
            looked.append(text)
            yield text

    result = tool(pasted).run({})
    assert result == "Video: Barış Özcan ile Röportaj\n(tr altyazı, otomatik)\n\n[Müzik] Merhaba sevgili izleyiciler"
    assert sent[0] == {"context": {"client": {"clientName": "ANDROID", "clientVersion": "20.10.38", "hl": "tr"}},
                       "videoId": "4gtWE9OOagw"}  # fmt: skip
    assert sent[1] == CAPTIONS
    # The selection (Ctrl+C on Windows) isn't read once the clipboard had the address.
    assert len(looked) == 1


def test_an_address_given_is_used_before_the_clipboard(monkeypatch):
    sent = fake_youtube(monkeypatch, [PLAYER])
    tool(lambda: iter(["https://youtu.be/dQw4w9WgXcQ"])).run({"address": "https://www.youtube.com/watch?v=4gtWE9OOagw"})
    assert sent[0]["videoId"] == "4gtWE9OOagw"


def test_the_next_client_is_asked_when_the_first_gets_no_captions(monkeypatch):
    unplayable = {"playabilityStatus": {"status": "LOGIN_REQUIRED"}}
    sent = fake_youtube(monkeypatch, [unplayable, PLAYER])
    tool().run({"address": "https://youtu.be/4gtWE9OOagw"})
    assert [payload["context"]["client"]["clientName"] for payload in sent[:2]] == ["ANDROID", "IOS"]


def test_no_address_anywhere_is_said():
    with pytest.raises(ToolError, match="Panoda ya da seçili metinde bir YouTube adresi bulamadım."):
        tool(lambda: iter(["merhaba", ""])).run({})
    with pytest.raises(ToolError, match="couldn't find a YouTube address"):
        tool(language=EN).run({"address": "https://vimeo.com/1"})


def test_a_video_without_captions_is_said(monkeypatch):
    fake_youtube(monkeypatch, [{"playabilityStatus": {"status": "OK"}}] * 2)
    with pytest.raises(ToolError, match="Bu videonun altyazısı yok"):
        tool().run({"address": "https://youtu.be/0WNOnVB3HO8"})


def test_empty_captions_count_as_none(monkeypatch):
    fake_youtube(monkeypatch, [PLAYER], captions=b"")
    with pytest.raises(ToolError, match="Bu videonun altyazısı yok"):
        tool().run({"address": "https://youtu.be/4gtWE9OOagw"})


def test_a_private_or_removed_video_is_said(monkeypatch):
    fake_youtube(monkeypatch, [{"playabilityStatus": {"status": "ERROR"}}] * 2)
    with pytest.raises(ToolError, match="Bu videoyu açamadım"):
        tool().run({"address": "https://youtu.be/4gtWE9OOagw"})


def test_when_youtube_cannot_be_reached_it_says_so(monkeypatch):
    error = web_fetch.WebFetchError(web_fetch.Reason.CONNECT)
    fake_youtube(monkeypatch, [error, error])
    with pytest.raises(ToolError, match="Videonun bilgilerini alamadım. Sunucuya bağlanamadım."):
        tool().run({"address": "https://youtu.be/4gtWE9OOagw"})


def test_devamini_ozetle_goes_on_with_the_transcript(monkeypatch):
    long_text = b"<transcript>" + b"".join(b"<text>kelime%d</text>" % i for i in range(4000)) + b"</transcript>"
    fake_youtube(monkeypatch, [PLAYER], captions=long_text)
    reading = TextReading(TR, clock=lambda: datetime(2026, 10, 25, 20, 0))
    video = tool(reading=reading)
    first = video.run({"address": "https://youtu.be/4gtWE9OOagw"})
    assert first.endswith("(Devamı var.)")
    arguments = video.refine({"address": ""}, "devamını özetle")
    assert arguments["continue"] is True
    assert video.run(arguments).startswith("Barış Özcan ile Röportaj, bölüm 2:")
    assert video.reads_untrusted({})
