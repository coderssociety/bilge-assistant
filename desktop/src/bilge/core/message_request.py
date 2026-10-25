"""The words of a text message as the user dictated them: "Ahmet'e mesaj at: geliyorum", "Ayşe'ye 'geç kalacağım'
diye SMS gönder", "geliyorum diye Ahmet'e mesaj yaz", "text Anna saying I'm on my way"."""

import re

from bilge.core import text

_MESSAGE_WORDS = ("mesaj", "sms", "message", "text")
# A quote opens at the start of a word, so the apostrophe in "Ayşe'ye" isn't taken for one.
_QUOTED = re.compile(r"(?:^|\s)[\"“”«»'‘’](.+?)[\"“”«»'‘’](?:\s|$)")
_ENGLISH_LEAD = re.compile(r"\b(?:saying|that says|and say|to say)\s+(.+)$", re.IGNORECASE)
# "Ahmet'e", "Ayşe'ye": the person the message goes to, which ends what comes before the message.
_TO_SOMEONE = re.compile(r"^[^\W\d_][\w.-]*['’](?:y?[ae]|n[ae])$", re.IGNORECASE)
_TRAILING = re.compile(r"[\s,.!]*(?:lütfen|please)?[\s,.!]*$", re.IGNORECASE)


def mentions_message(said: str) -> bool:
    return any(word.startswith(_MESSAGE_WORDS) for word in text.folded(said).split())


def message_text(command: str) -> str | None:
    """None when the command doesn't plainly say the words; the model's wording is then read back for a yes."""
    if not mentions_message(command):
        return None
    head, colon, tail = command.partition(":")
    if colon and mentions_message(head) and tail.strip():
        return _clean(tail)
    quoted = _QUOTED.search(command)
    if quoted is not None:
        return _clean(quoted.group(1))
    english = _ENGLISH_LEAD.search(command)
    if english is not None:
        return _clean(english.group(1))
    words = command.split()
    folds = [text.folded(word) for word in words]
    if "diye" not in folds:
        return None
    end = folds.index("diye")
    start = max((i + 1 for i in range(end) if _TO_SOMEONE.match(words[i]) or folds[i].startswith(_MESSAGE_WORDS)),
                default=0)  # fmt: skip
    return _clean(" ".join(words[start:end]))


def _clean(said: str) -> str | None:
    cleaned = _TRAILING.sub("", said.strip().strip("\"“”«»'‘’")).strip()
    return cleaned or None
