"""Whether a request about e-mail wants the messages themselves or only how many there are and from whom:
"maillerimi oku" and "içeriğini oku" read them, "kaç mailim var" counts them."""

from bilge.core import text

_CONTENT_WORDS = ("oku", "icerig", "icerik", "yaziyor", "yazmis", "yazdi", "yazilmis", "detay", "ayrinti", "ozet",
                  "anlat", "metin", "metni", "read", "content", "says", "say", "summar", "body", "detail")  # fmt: skip


def asks_for_content(command: str) -> bool:
    return any(word.startswith(_CONTENT_WORDS) for word in text.folded(command).split())
