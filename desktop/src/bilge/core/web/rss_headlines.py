"""Items from an RSS 2.0 or Atom feed, in feed order."""

import contextlib
from dataclasses import dataclass
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime
from urllib.parse import urlsplit
from xml.parsers import expat


@dataclass(frozen=True)
class Item:
    title: str
    # The article's address, when the feed gives one over http(s).
    link: str | None
    # The attached audio or video (a podcast episode), over http(s).
    enclosure: str | None = None
    published: datetime | None = None


class _LimitReached(Exception):
    pass


_FIELDS = frozenset({"title", "link", "pubDate", "published", "updated"})


class _Collector:
    def __init__(self, limit: int) -> None:
        self.limit = limit
        self.items: list[Item] = []
        self._in_item = False
        self._values: dict[str, str] = {}
        self._enclosure: str | None = None
        self._field: str | None = None
        self._current: list[str] | None = None

    def start(self, name: str, attributes: dict[str, str]) -> None:
        if name in ("item", "entry"):
            self._in_item = True
            self._values, self._enclosure = {}, None
        if not self._in_item:
            return
        rel = attributes.get("rel", "alternate")
        if name == "enclosure" or (name == "link" and rel == "enclosure"):
            self._enclosure = self._enclosure or _media(attributes)
            return
        if name not in _FIELDS:
            return
        self._field, self._current = name, []
        # Atom gives the address as an attribute: <link rel="alternate" href="…"/>.
        if name == "link" and "href" in attributes and rel == "alternate":
            self._values["link"] = attributes["href"]

    def characters(self, text: str) -> None:
        if self._current is not None:
            self._current.append(text)

    def end(self, name: str) -> None:
        if name == self._field and self._current is not None:
            cleaned = "".join(self._current).strip()
            if cleaned:
                self._values[name] = cleaned
            self._field = self._current = None
        if name not in ("item", "entry"):
            return
        self._in_item = False
        title = self._values.get("title")
        if title:
            link = self._values.get("link")
            when = self._values.get("pubDate") or self._values.get("published") or self._values.get("updated")
            self.items.append(Item(title, link if _is_web(link) else None, self._enclosure, _date(when)))
        if len(self.items) >= self.limit:
            raise _LimitReached


def _is_web(url: str | None) -> bool:
    return bool(url) and urlsplit(url).scheme in ("http", "https")


def _media(attributes: dict[str, str]) -> str | None:
    url = attributes.get("url") or attributes.get("href")
    kind = attributes.get("type", "")
    if not _is_web(url) or (kind and not kind.startswith(("audio/", "video/"))):
        return None
    return url


def _date(text: str | None) -> datetime | None:
    """RSS dates (RFC 822) and Atom ones (ISO 8601); a date without a zone ("-0000") is taken as UTC."""
    if not text:
        return None
    try:
        found = parsedate_to_datetime(text)
    except (TypeError, ValueError, IndexError):
        try:
            found = datetime.fromisoformat(text.replace("Z", "+00:00"))
        except ValueError:
            return None
    return found if found.tzinfo else found.replace(tzinfo=UTC)


def items(data: bytes, limit: int) -> list[Item]:
    """Items found before the limit or the first XML error; a broken feed still yields what came before it."""
    collector = _Collector(limit)
    parser = expat.ParserCreate()
    parser.StartElementHandler = collector.start
    parser.CharacterDataHandler = collector.characters
    parser.EndElementHandler = collector.end
    with contextlib.suppress(_LimitReached, expat.ExpatError):
        parser.Parse(data, True)
    return collector.items


def parse(data: bytes, limit: int) -> list[str]:
    return [item.title for item in items(data, limit)]
