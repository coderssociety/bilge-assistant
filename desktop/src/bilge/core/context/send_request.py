"""'Bunu Ahmet'e gönder', 'seçili metni ahmet@ornek.com adresine mail at', 'send this to Anna': sending what the user
points at by e-mail. Only the recipient and the pointing words are taken from the command; the text itself is read
when the message is prepared, so the model never sees or chooses it."""

import re
from dataclasses import dataclass

from bilge.core.context import context_intent
from bilge.core.language import AssistantLanguage
from bilge.core.text import folded


@dataclass(frozen=True)
class SendRequest:
    recipient: str
    # The pointing words as said ("bunu", "bu metni", "this"), which the e-mail tool resolves to the text.
    pointer: str


_EMAIL = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")
# "Ahmet'e", "Ayşe'ye", "Ahmet Yılmaz'a": a name with the dative ending; only capitalized words join a name.
_TURKISH_RECIPIENT = re.compile(r"((?:[A-ZÇĞİÖŞÜ][\w-]*\s+){0,2}[^\W\d_][\w.-]*)['’]y?[ae]\b")
_OBJECT_POINTERS = frozenset({"bunu", "sunu", "bunlari", "sunlari"})
_TURKISH_SEND_WORDS = ("gonder", "yolla", "ilet")
_TURKISH_MAIL_WORDS = ("mail", "eposta", "e-posta", "posta")
# Another channel, or words dictated for the message, are not "send this".
_OTHER_CHANNELS = ("mesaj", "sms", "whatsapp", "telegram", "message")
_DICTATION_MARKS = re.compile(r"[\"“”«»:]|\bdiye\b|\bsaying\b", re.IGNORECASE)
_ENGLISH = re.compile(
    r"^(?:please\s+)?(?:send|email|e-mail|mail|forward)\s+(?P<pointer>(?:this|that|these|those)(?:\s+\w+)?"
    r"|the\s+selected\s+\w+|the\s+selection)\s+to\s+(?P<to>.+?)(?:\s+(?:by|via)\s+e-?mail)?(?:\s+please)?[.!?]?$",
    re.IGNORECASE,
)


def parse(command: str, language: AssistantLanguage = AssistantLanguage.TURKISH) -> SendRequest | None:
    if _DICTATION_MARKS.search(command):
        return None
    words = folded(command).split()
    if any(word.startswith(_OTHER_CHANNELS) for word in words):
        return None
    if language is AssistantLanguage.ENGLISH:
        return _english(command)
    return _turkish(command, words)


def _turkish(command: str, words: list[str]) -> SendRequest | None:
    sends = any(word.startswith(_TURKISH_SEND_WORDS) for word in words)
    mails = any(word.startswith(_TURKISH_MAIL_WORDS) for word in words) and ("at" in words or sends)
    if not (sends or mails):
        return None
    pointer = _turkish_pointer(command)
    recipient = _recipient(command)
    if pointer is None or recipient is None:
        return None
    return SendRequest(recipient, pointer)


def _turkish_pointer(command: str) -> str | None:
    """The object pointed at: "bunu", "şunları", or a pointing word with a kind ("bu metni", "seçili dosyayı").
    A bare "bu" is left out, as it starts "bu akşam" as often as anything on screen."""
    original = command.split()
    for index, word in enumerate(original):
        pair = " ".join(original[index : index + 2])
        if index + 1 < len(original) and context_intent.only_points(pair) and context_intent.wanted_kind(pair):
            return pair
        if folded(word) in _OBJECT_POINTERS:
            return word
    return None


def _recipient(command: str) -> str | None:
    email = _EMAIL.search(command)
    if email is not None:
        return email.group(0)
    found = _TURKISH_RECIPIENT.search(command)
    if found is None:
        return None
    # "Bunu Ahmet'e": a capitalized pointing word is not part of the name.
    words = found.group(1).split()
    while words and context_intent.only_points(words[0]):
        words = words[1:]
    return " ".join(words) or None


def _english(command: str) -> SendRequest | None:
    found = _ENGLISH.match(command.strip())
    if found is None:
        return None
    pointer = found.group("pointer")
    recipient = found.group("to").strip()
    if not context_intent.only_points(pointer, AssistantLanguage.ENGLISH) or not recipient:
        return None
    email = _EMAIL.search(recipient)
    return SendRequest(email.group(0) if email else recipient, pointer)
