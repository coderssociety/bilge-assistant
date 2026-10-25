"""What a request about e-mail asks for: the messages themselves or only how many there are and from whom
("maillerimi oku" and "içeriğini oku" read them, "kaç mailim var" counts them), whose mail ("Ahmet'in mailini oku"),
which one ("ikinci maili oku", "son mailimi oku"), and the words of a reply ("buna yanıt ver: yarın uygunum",
"teşekkür ederim diye cevap yaz", "reply saying thanks")."""

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


_REPLY_STEMS = ("yanit", "cevap", "reply", "answer", "respond")
_REPLY_VERBS = frozenset({"ver", "yaz", "gonder", "at", "olarak", "verir", "yazar", "yazsana", "versene"})
_REFERENCES = frozenset({"buna", "ona", "suna", "bunu", "onu"})
# In order: "reply to that email saying thanks" is answered with "thanks".
_ENGLISH_LEADS = tuple(
    re.compile(rf"\b{lead}\s+(.+)$", re.IGNORECASE)
    for lead in ("saying", "to say", "and say", "and tell (?:him|her|them)", "with", "that")
)
_QUOTED = re.compile(r"[\"“”«»](.+?)[\"“”«»]")
_NAME_WITH_ENDING = re.compile(r"^[A-ZÇĞİÖŞÜ][^\W\d_]*['’][^\W\d_]+$")
_TRAILING = re.compile(r"[\s,.!]*(?:lütfen|please)?[\s,.!]*$", re.IGNORECASE)


def asks_to_reply(command: str) -> bool:
    return any(word.startswith(_REPLY_STEMS) for word in text.folded(command).split())


def reply_text(command: str) -> str | None:
    """The words the user dictated for a reply, exactly as said; None when there are none. Only the command's own
    words count, never anything from the message being answered."""
    if not asks_to_reply(command):
        return None
    head, colon, tail = command.partition(":")
    if colon and asks_to_reply(head) and tail.strip():
        return _clean(tail)
    quoted = _QUOTED.search(command)
    if quoted is not None:
        return _clean(quoted.group(1))
    words = command.split()
    folds = [text.folded(word) for word in words]
    if "diye" in folds:
        end = folds.index("diye")
        start = max((i + 1 for i in range(end) if _is_reference(words[i], folds[i])), default=0)
        return _clean(" ".join(words[start:end]))
    for lead in _ENGLISH_LEADS:
        english = lead.search(command)
        if english is not None:
            return _clean(english.group(1))
    reply = next(i for i, fold in enumerate(folds) if fold.startswith(_REPLY_STEMS))
    rest = reply + 1
    while rest < len(words) and folds[rest] in _REPLY_VERBS:
        rest += 1
    end = len(words)
    while end > rest and folds[end - 1] in ("lutfen", "please"):
        end -= 1
    # "cevap olarak tamam yaz"
    if "olarak" in folds[reply:rest] and end > rest + 1 and folds[end - 1] in _REPLY_VERBS:
        end -= 1
    return _clean(" ".join(words[rest:end]))


def only_said(words: str, command: str) -> str:
    """`words` when every one of them was said in the command, otherwise nothing: a model's reply text must not bring
    in anything else, such as words from the message it answers."""
    said = set(text.folded(command).split())
    return words.strip() if words.strip() and all(word in said for word in text.folded(words).split()) else ""


def _is_reference(word: str, fold: str) -> bool:
    """A word naming what is answered or whom: "buna", "mailine", "Ahmet'e"."""
    return fold in _REFERENCES or fold.startswith(_MAIL_WORDS) or bool(_NAME_WITH_ENDING.match(word))


def _clean(said: str) -> str | None:
    cleaned = _TRAILING.sub("", said.strip().strip("\"“”«»'")).strip()
    return cleaned or None
