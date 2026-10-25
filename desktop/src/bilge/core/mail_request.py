"""What a request about e-mail asks for: the messages themselves or only how many there are and from whom
("maillerimi oku" and "içeriğini oku" read them, "kaç mailim var" counts them), whose mail ("Ahmet'in mailini oku"),
and which one ("ikinci maili oku", "son mailimi oku")."""

import re

from bilge.core import text

_CONTENT_WORDS = ("oku", "icerig", "icerik", "yaziyor", "yazmis", "yazdi", "yazilmis", "detay", "ayrinti", "ozet",
                  "anlat", "metin", "metni", "read", "content", "says", "say", "summar", "body", "detail")  # fmt: skip
_MAIL_WORDS = ("mail", "eposta", "posta", "ileti", "mesaj", "email", "message")
_LATEST_WORDS = frozenset({"son", "sonuncu", "latest", "last", "newest", "recent"})
_ORDINAL_WORDS = {
    "ilk": 1, "birinci": 1, "onuncu": 10, "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6,
    "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10,
}  # fmt: skip
# After turkish_number_parser: "2'nci", "3'üncü", folded to "2nci", "3uncu"; English "2nd".
_ORDINAL = re.compile(r"^(\d+)(?:inci|nci|uncu|ncu|st|nd|rd|th)$")
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
    for word in words:
        found = _ORDINAL.match(word)
        if found is not None and int(found.group(1)) > 0:
            return int(found.group(1))
        if word in _ORDINAL_WORDS:
            return _ORDINAL_WORDS[word]
    return 1 if any(word in _LATEST_WORDS for word in words) else None
