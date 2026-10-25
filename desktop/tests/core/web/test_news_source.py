import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.web import news_source
from bilge.core.web.news_source import NewsSource

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH


@pytest.mark.parametrize(
    ("command", "language", "source"),
    [
        ("TRT'den haberleri oku", TR, NewsSource.TRT_HABER),
        ("BBC haberleri", TR, NewsSource.BBC_TURKISH),
        ("AA'dan son başlıklar", TR, NewsSource.ANADOLU),
        ("Anadolu Ajansı ne diyor", TR, NewsSource.ANADOLU),
        ("news from the Guardian", EN, NewsSource.GUARDIAN),
        ("BBC headlines", EN, NewsSource.BBC_NEWS),
        ("what's on NPR", EN, NewsSource.NPR),
        ("Bugünün haberleri", TR, None),
        ("aaaa haberleri", TR, None),
    ],
)
def test_finds_a_named_source(command: str, language: AssistantLanguage, source: NewsSource | None) -> None:
    assert news_source.named(command, language) is source


@pytest.mark.parametrize(
    ("command", "asks"),
    [
        ("Başka bir kaynak", True),
        ("farklı bir siteden oku", True),
        ("diğer kaynaklarda ne var", True),
        ("another source please", True),
        ("somewhere else", True),
        ("Başka var mı", False),
        ("bu kaynak güvenilir mi", False),
        ("başka haber", False),
    ],
)
def test_knows_a_request_for_another_source(command: str, asks: bool) -> None:
    assert news_source.asks_for_another(command) is asks


def test_the_next_source_goes_round_skipping_one_without_a_feed_for_the_topic() -> None:
    assert NewsSource.ANADOLU.next("general") is NewsSource.TRT_HABER
    assert NewsSource.TRT_HABER.next("general") is NewsSource.BBC_TURKISH
    assert NewsSource.BBC_TURKISH.next("general") is NewsSource.ANADOLU
    assert NewsSource.TRT_HABER.next("technology") is NewsSource.ANADOLU
    assert NewsSource.NPR.next("sports") is NewsSource.BBC_NEWS


def test_every_source_has_a_general_feed_over_https() -> None:
    for source in NewsSource:
        assert (source.feed("general") or "").startswith("https://")
    assert NewsSource.TRT_HABER.feed("technology") == "https://www.trthaber.com/bilim_teknoloji_articles.rss"
    assert NewsSource.BBC_TURKISH.feed("sports") is None
