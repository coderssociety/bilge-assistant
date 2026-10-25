from datetime import datetime, timedelta, timezone

import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.media.playback_state import Kind, Source
from bilge.tools import web_fetch
from bilge.tools.base import ToolError
from bilge.tools.builtin import podcasts
from bilge.tools.player import PlaybackError

from .fake_player import FakePlayer

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
NOW = datetime(2026, 10, 25, 20, 0, tzinfo=timezone(timedelta(hours=3)))
FEED_URL = "https://feeds.example/PM5261345791"
SEARCH = {"resultCount": 1, "results": [{"collectionName": "Fularsız Entellik", "feedUrl": FEED_URL}]}
FEED = b"""<rss><channel><title>Fularsiz Entellik</title>
<item><title>Eski</title><pubDate>Sun, 11 Oct 2026 02:00:00 -0000</pubDate>
<enclosure url="https://traffic.example/old.mp3" type="audio/mpeg"/></item>
<item><title>Pop\xc3\xbclizm</title><pubDate>Sun, 18 Oct 2026 02:00:00 -0000</pubDate>
<enclosure url="https://traffic.example/new.mp3" type="audio/mpeg"/></item>
</channel></rss>"""


def fake_web(monkeypatch, searches, feed=FEED, feed_status=200):
    """`searches` maps a search term to Apple's answer; any other term finds nothing."""
    asked = []

    def get_json(url, language, user_agent=""):
        asked.append(url)
        return next((answer for term, answer in searches.items() if f"term={term}&" in url), {"results": []})

    def get(url, language=TR, max_bytes=0, user_agent=""):
        asked.append(url)
        return web_fetch.Response(url, feed_status, "application/rss+xml", feed)

    monkeypatch.setattr(podcasts, "get_json", get_json)
    monkeypatch.setattr(web_fetch, "get", get)
    return asked


def tool(player, language=TR, now=NOW):
    return podcasts.podcast_tool(language, player, clock=lambda: now)


def test_the_newest_episode_plays_under_the_name_said(monkeypatch):
    asked = fake_web(monkeypatch, {"Fulars%C4%B1z+Entellik": SEARCH})
    player = FakePlayer()
    reply = tool(player).run({"action": "latest", "podcast": "Fularsız Entellik"})
    assert reply == "Fularsız Entellik podcastinin son bölümü çalıyor (18 Ekim Pazar yayımlandı)."
    assert player.played == [Source(Kind.EPISODE, "Fularsız Entellik", "https://traffic.example/new.mp3",
                                    title="Popülizm")]  # fmt: skip
    assert asked[0].startswith("https://itunes.apple.com/search?media=podcast&term=") and "country=tr" in asked[0]
    assert asked[-1] == FEED_URL


def test_a_glued_genitive_is_searched_again_without_it(monkeypatch):
    asked = fake_web(monkeypatch, {"Fulars%C4%B1z+Entellik": SEARCH})
    reply = tool(FakePlayer()).run({"action": "latest", "podcast": "Fularsız Entellikin"})
    assert "Entellikin" in asked[0] and "Entellik&" in asked[1]
    assert reply.startswith("Fularsız Entellik podcastinin")


def test_a_new_episode_is_reported_with_its_title(monkeypatch):
    fake_web(monkeypatch, {"Fulars%C4%B1z+Entellik": SEARCH})
    podcast = tool(FakePlayer(), now=NOW - timedelta(days=3))
    assert podcast.run({"action": "check", "podcast": "Fularsız Entellik"}) == (
        "Evet, Fularsız Entellik podcastinin yeni bölümü 18 Ekim Pazar yayımlandı: Popülizm"
    )
    assert podcast.reads_untrusted({"action": "check"}) and not podcast.reads_untrusted({"action": "latest"})


def test_an_old_last_episode_is_not_new(monkeypatch):
    fake_web(monkeypatch, {"The+Show": SEARCH})
    reply = tool(FakePlayer(), EN, NOW + timedelta(days=30)).run({"action": "check", "podcast": "The Show"})
    assert reply.startswith("Nothing new this week. The latest episode of The Show came out Sunday 18 October")
    next_year = tool(FakePlayer(), TR, NOW + timedelta(days=400)).run({"action": "check", "podcast": "The Show"})
    assert "son bölümü 18 Ekim 2026 yayımlandı" in next_year


def test_an_unknown_show_is_said(monkeypatch):
    fake_web(monkeypatch, {})
    with pytest.raises(ToolError, match="'Uydurma' adında bir podcast bulamadım."):
        tool(FakePlayer()).run({"action": "latest", "podcast": "Uydurma"})


def test_a_feed_that_fails_or_has_no_audio_is_said(monkeypatch):
    fake_web(monkeypatch, {"X": SEARCH}, feed_status=404)
    with pytest.raises(ToolError, match="X podcastinin bölüm listesini alamadım. Sayfa bulunamadı."):
        tool(FakePlayer()).run({"action": "latest", "podcast": "X"})
    fake_web(monkeypatch, {"X": SEARCH}, feed=b"<rss><channel><item><title>A</title></item></channel></rss>")
    with pytest.raises(ToolError, match="X podcastinde çalınabilecek bir bölüm bulamadım."):
        tool(FakePlayer()).run({"action": "latest", "podcast": "X"})


def test_an_episode_that_will_not_start_is_said(monkeypatch):
    fake_web(monkeypatch, {"X": SEARCH})
    player = FakePlayer(error=PlaybackError(None))
    with pytest.raises(ToolError, match="Bölümü açamadım. Yayının ses biçimini çalamıyorum."):
        tool(player).run({"action": "latest", "podcast": "X"})


def test_the_rule_reads_the_show_and_the_action():
    assert podcasts.rule_arguments("Fularsız Entellik podcastinin son bölümünü aç") == {
        "action": "latest",
        "podcast": "Fularsız Entellik",
    }
    assert podcasts.claims("Nasıl Olunur'un yeni bölümü var mı")
    assert not podcasts.claims("radyo aç")
