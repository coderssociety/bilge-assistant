"""What a request about e-mail asks for: the messages themselves or only how many there are and from whom
("maillerimi oku" and "içeriğini oku" read them, "kaç mailim var" counts them), whose mail ("Ahmet'in mailini oku"),
and which one ("ikinci maili oku", "son mailimi oku")."""

import re

from bilge.core import text
from bilge.core.tools import ordinal

_CONTENT_WORDS = ("oku", "icerig", "icerik", "yaziyor", "yazmis", "yazdi", "yazilmis", "detay", "ayrinti", "ozet",
                  "anlat", "metin", "metni", "read", "content", "says", "say", "summar", "body", "detail")  # fmt: skip
_MAIL_WORDS = ("mail", "eposta", "posta", "ileti", "mesaj", "email", "message")
_LATEST_WORDS = frozenset({"son", "sonuncu", "latest", "last", "newest", "recent"})
_TURKISH_SENDER = re.compile(
    r"([^\W\d_][\w.@-]*)['’](?:n?[ıiuü]n\s+(?:en\s+)?(?:\S+\s+)?(?:e-?posta|mail|ileti|mesaj)"
    r"|[dt][ae]n\s+(?:gelen|son))",
    re.IGNORECASE,
)
_ENGLISH_SENDER = re.compile(
    r"\bfrom\s+([^\W\d_][\w.@-]*)|([^\W\d_][\w.@-]*)['’]s\s+(?:(?:latest|last|newest)\s+)?(?:e-?mail|mail|message)",
    re.IGNORECASE,
)
_NOT_SENDERS = frozenset({"the", "my", "a", "an", "today", "yesterday", "work", "home", "this", "last", "outlook",
                          "inbox", "him", "her", "them"})  # fmt: skip


def asks_for_content(command: str) -> bool:
    return any(word.startswith(_CONTENT_WORDS) for word in text.folded(command).split())


def sender(command: str) -> str | None:
    """The person whose mail is asked for, as said: "Ahmet'in mailini oku", "Ahmet'ten gelen", "mail from Anna"."""
    for pattern in (_TURKISH_SENDER, _ENGLISH_SENDER):
        found = pattern.search(command)
        if found is not None:
            name = next(group for group in found.groups() if group)
            if name.lower() not in _NOT_SENDERS:
                return name
    return None


def position(command: str) -> int | None:
    """Which message, newest first: "ikinci maili oku" → 2, "son mailimi oku" → 1; None when none is picked out."""
    words = text.folded(command).split()
    if not any(word.startswith(_MAIL_WORDS) for word in words):
        return None
    place = ordinal.in_words(words)
    # The last mail is the newest one.
    if place == ordinal.LAST or (place is None and any(word in _LATEST_WORDS for word in words)):
        return 1
    return place
