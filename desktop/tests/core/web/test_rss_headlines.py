from datetime import UTC, datetime, timedelta, timezone

from bilge.core.web import rss_headlines

PODCAST = b"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel><title>Fularsiz Entellik</title>
<item>
  <title>Pop\xc3\xbclizm</title>
  <pubDate>Sun, 18 Oct 2026 02:00:00 -0000</pubDate>
  <itunes:duration>1896</itunes:duration>
  <enclosure url="https://traffic.example/PM1.mp3" length="0" type="audio/mpeg"/>
</item>
<item>
  <title>Kapak resmi</title>
  <pubDate>Sat, 17 Oct 2026 10:00:00 +0300</pubDate>
  <enclosure url="https://cdn.example/cover.jpg" type="image/jpeg"/>
</item>
<item>
  <title>Yerel</title>
  <enclosure url="file:///etc/passwd" type="audio/mpeg"/>
</item>
</channel></rss>"""

ATOM = b"""<feed xmlns="http://www.w3.org/2005/Atom">
<entry><title>Bolum 3</title><link rel="alternate" href="https://show.example/3"/>
<link rel="enclosure" href="https://show.example/3.m4a" type="audio/mp4"/>
<published>2026-10-20T08:30:00Z</published><updated>2026-10-21T08:30:00Z</updated></entry>
</feed>"""


def test_episodes_carry_their_audio_and_date():
    first, cover, local = rss_headlines.items(PODCAST, 10)
    assert first.enclosure == "https://traffic.example/PM1.mp3"
    # "-0000" says nothing of the zone; it is read as UTC.
    assert first.published == datetime(2026, 10, 18, 2, tzinfo=UTC)
    assert cover.enclosure is None
    assert cover.published == datetime(2026, 10, 17, 10, tzinfo=timezone(timedelta(hours=3)))
    assert local.enclosure is None and local.published is None


def test_atom_enclosures_and_publishing_date():
    (entry,) = rss_headlines.items(ATOM, 10)
    assert entry.link == "https://show.example/3"
    assert entry.enclosure == "https://show.example/3.m4a"
    assert entry.published == datetime(2026, 10, 20, 8, 30, tzinfo=UTC)


def test_titles_still_read_and_a_broken_date_is_none():
    feed = b"<rss><channel><item><title>A</title><pubDate>sometime</pubDate></item></channel></rss>"
    assert rss_headlines.parse(feed, 5) == ["A"]
    assert rss_headlines.items(feed, 5)[0].published is None
