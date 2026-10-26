from datetime import UTC, datetime

import pytest

from bilge.core.media import podcasts
from bilge.core.media.podcasts import PodcastAction, PodcastRequest
from bilge.core.web.rss_headlines import Item

LATEST, CHECK = PodcastAction.LATEST, PodcastAction.CHECK


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("Fularsız Entellik podcastinin son bölümünü aç", PodcastRequest(LATEST, "Fularsız Entellik")),
        ("Bilge, Kendime Not podcastinin son bölümünü açar mısın", PodcastRequest(LATEST, "Kendime Not")),
        ("Yeni Bir Gün podcastini aç", PodcastRequest(LATEST, "Yeni Bir Gün")),
        ("Nasıl Olunur'un yeni bölümü var mı", PodcastRequest(CHECK, "Nasıl Olunur")),
        ("Fularsız Entellikin yeni bölümü çıktı mı", PodcastRequest(CHECK, "Fularsız Entellikin")),
        ("Fularsız Entellik podcastinde yeni bölüm var mı", PodcastRequest(CHECK, "Fularsız Entellik")),
        ("play the latest episode of The Daily", PodcastRequest(LATEST, "The Daily")),
        ("is there a new episode of Huberman Lab?", PodcastRequest(CHECK, "Huberman Lab")),
    ],
)
def test_podcast_requests(command, expected):
    assert podcasts.parse(command) == expected


@pytest.mark.parametrize(
    "command", ["Medcezir'in son bölümünü aç", "son bölümü aç", "yeni bölüm var mı", "müziği aç", "radyo aç"]
)
def test_series_and_nameless_requests_are_left_to_the_model(command):
    assert podcasts.parse(command) is None


def test_a_glued_genitive_is_tried_without_it_second():
    assert podcasts.search_terms("Fularsız Entellikin") == ["Fularsız Entellikin", "Fularsız Entellik"]
    assert podcasts.search_terms("Nasıl Olunur") == ["Nasıl Olunur"]


def test_the_show_named_exactly_wins():
    results = {"results": [
        {"collectionName": "Büyük Marka Nasıl Olunur?", "feedUrl": "https://a.example/feed"},
        {"collectionName": "Nasıl Olunur", "feedUrl": "https://b.example/feed"},
        {"collectionName": "Nasıl Olunur 2", "feedUrl": "ftp://c.example/feed"},
        "junk",
    ]}  # fmt: skip
    assert podcasts.choose(results, "nasıl olunur") == podcasts.Show("Nasıl Olunur", "https://b.example/feed")
    assert podcasts.choose(results, "başka bir şey").feed == "https://a.example/feed"
    assert podcasts.choose({"resultCount": 0, "results": []}, "x") is None
    assert podcasts.choose(None, "x") is None


def test_the_newest_episode_with_audio_is_taken_whatever_the_feed_order():
    old = Item("Eski", None, "https://cdn.example/1.mp3", datetime(2026, 9, 1, tzinfo=UTC))
    new = Item("Yeni", None, "https://cdn.example/2.mp3", datetime(2026, 10, 18, tzinfo=UTC))
    trailer = Item("Fragman", None, None, datetime(2026, 10, 20, tzinfo=UTC))
    assert podcasts.latest([old, trailer, new]) == new
    assert podcasts.latest([Item("Tarihsiz", None, "https://cdn.example/3.mp3")]).title == "Tarihsiz"
    assert podcasts.latest([trailer]) is None
