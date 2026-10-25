"""Where the headlines come from. Each language has a few, read in turn when the user asks for another source
("başka bir kaynak"), or by name ("TRT haberleri")."""

from enum import Enum

from bilge.core import text
from bilge.core.language import AssistantLanguage
from bilge.core.web.news_request import TOPICS


class NewsSource(Enum):
    ANADOLU = "anadolu"
    TRT_HABER = "trtHaber"
    BBC_TURKISH = "bbcTurkish"
    BBC_NEWS = "bbcNews"
    GUARDIAN = "guardian"
    NPR = "npr"

    @property
    def language(self) -> AssistantLanguage:
        return AssistantLanguage.TURKISH if self in sources(AssistantLanguage.TURKISH) else AssistantLanguage.ENGLISH

    @property
    def from_(self) -> str:
        """The source in a sentence about where the headlines come from: "Anadolu Ajansı'ndan", "from BBC News"."""
        return _FROM[self]

    def feed(self, topic: str) -> str | None:
        """The feed for `topic`; None where the source has no feed of its own for it (BBC Türkçe has one feed)."""
        slugs = _FEEDS[self]
        index = TOPICS.index(topic) if topic in TOPICS else 0
        return slugs[index] if index < len(slugs) else None

    def next(self, topic: str) -> "NewsSource":
        """The source after this one, in its language, that has a feed for `topic`."""
        others = sources(self.language)
        start = others.index(self)
        return next(
            (s for s in (others[(start + n) % len(others)] for n in range(1, len(others))) if s.feed(topic)), self
        )


def sources(language: AssistantLanguage) -> list[NewsSource]:
    if language is AssistantLanguage.TURKISH:
        return [NewsSource.ANADOLU, NewsSource.TRT_HABER, NewsSource.BBC_TURKISH]
    return [NewsSource.BBC_NEWS, NewsSource.GUARDIAN, NewsSource.NPR]


def preferred(language: AssistantLanguage) -> NewsSource:
    return sources(language)[0]


_FROM = {
    NewsSource.ANADOLU: "Anadolu Ajansı'ndan",
    NewsSource.TRT_HABER: "TRT Haber'den",
    NewsSource.BBC_TURKISH: "BBC Türkçe'den",
    NewsSource.BBC_NEWS: "from BBC News",
    NewsSource.GUARDIAN: "from The Guardian",
    NewsSource.NPR: "from NPR",
}
# In the order of TOPICS: general, economy, sports, world, technology.
_FEEDS = {
    NewsSource.ANADOLU: [f"https://www.aa.com.tr/tr/rss/default?cat={slug}" for slug in
                         ("guncel", "ekonomi", "spor", "dunya", "bilim-teknoloji")],
    NewsSource.TRT_HABER: [f"https://www.trthaber.com/{slug}_articles.rss" for slug in
                           ("manset", "ekonomi", "spor", "dunya", "bilim_teknoloji")],
    NewsSource.BBC_TURKISH: ["https://feeds.bbci.co.uk/turkce/rss.xml"],
    NewsSource.BBC_NEWS: [f"https://feeds.bbci.co.uk/{path}" for path in
                          ("news/rss.xml", "news/business/rss.xml", "sport/rss.xml", "news/world/rss.xml",
                           "news/technology/rss.xml")],
    NewsSource.GUARDIAN: [f"https://www.theguardian.com/{section}/rss" for section in
                          ("international", "business", "sport", "world", "technology")],
    NewsSource.NPR: [f"https://feeds.npr.org/{topic}/rss.xml" for topic in ("1001", "1006", "1055", "1004", "1019")],
}  # fmt: skip
_OTHER_WORDS = ("baska", "farkli", "diger", "another", "other", "different", "else")
_SOURCE_WORDS = ("kaynak", "site", "yerden", "ajans", "kanal", "gazete", "source", "outlet", "paper", "somewhere")


def named(command: str, language: AssistantLanguage) -> NewsSource | None:
    """The source a command names: "TRT'den haberler", "BBC haberleri", "Anadolu Ajansı"."""
    for word in _words(command):
        # "AA'dan": the apostrophe is dropped, so "aa" with a short ending.
        if word.startswith("aa") and len(word) <= 5 and word[2:3] != "a":
            return NewsSource.ANADOLU
        if word.startswith("anadolu"):
            return NewsSource.ANADOLU
        if word.startswith("trt"):
            return NewsSource.TRT_HABER
        if word.startswith("bbc"):
            return NewsSource.BBC_TURKISH if language is AssistantLanguage.TURKISH else NewsSource.BBC_NEWS
        if word.startswith("guardian"):
            return NewsSource.GUARDIAN
        if word.startswith("npr"):
            return NewsSource.NPR
    return None


def asks_for_another(command: str) -> bool:
    """ "Başka bir kaynak", "farklı bir siteden", "another source", "somewhere else"."""
    words = _words(command)
    return any(w.startswith(_OTHER_WORDS) for w in words) and any(w.startswith(_SOURCE_WORDS) for w in words)


def _words(command: str) -> list[str]:
    return [word for word in text.folded(command).split() if word.isalpha()]
