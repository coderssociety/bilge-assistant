"""Smart-home commands for Home Assistant: whether a command names a home device or room ("salonun ışığını aç",
"klimayı 22 dereceye ayarla", "kapı kilitli mi"), whether it acts on something that guards the house (a lock, the
garage door, the alarm) and so needs a yes first, and what Home Assistant's conversation API sends back."""

from typing import Any
from urllib.parse import urlsplit, urlunsplit

from bilge.core.language import AssistantLanguage
from bilge.core.text import folded

# Folded word beginnings: "ışığını" → "isigini", "kilidi" → "kilidi".
_TURKISH_DEVICES = (
    "isik", "isig", "lamba", "avize", "klima", "priz", "perde", "panjur", "stor", "kilit", "kilid", "termostat",
    "kombi", "isitici", "petek", "salon", "mutfa", "garaj", "banyo", "koridor", "balkon",
)  # fmt: skip
_TURKISH_PHRASES = (("yatak", "odas"), ("oturma", "odas"), ("cocuk", "odas"), ("calisma", "odas"), ("ev", "alarm"),
                    ("guvenlik", "alarm"))  # fmt: skip
_ENGLISH_DEVICES = (
    "light", "lights", "lamp", "lamps", "thermostat", "plug", "plugs", "outlet", "outlets", "curtain", "curtains",
    "blind", "blinds", "shutter", "shutters", "lock", "locked", "unlock", "garage", "kitchen", "bedroom",
    "hallway", "heater", "heating",
)  # fmt: skip
_ENGLISH_PHRASES = (("living", "room"), ("air", "conditioning"), ("air", "conditioner"), ("front", "door"),
                    ("house", "alarm"), ("security", "alarm"), ("the", "ac"))  # fmt: skip
# "ekranın ışığını kıs", "bilgisayarı kilitle", "keyboard light": this computer, not the house.
_COMPUTER = ("ekran", "bilgisayar", "klavye", "mac", "telefon", "oturum", "screen", "computer", "keyboard",
             "display", "laptop", "phone")  # fmt: skip
_TURKISH_GUARDS = ("kilit", "kilid", "garaj", "alarm")
_ENGLISH_GUARDS = ("lock", "unlock", "garage", "alarm")
_TURKISH_QUESTION = frozenset({"mi", "mı", "mu", "mü", "misin", "mıdır", "midir", "mudur", "müdür", "ne", "kaç",
                               "nedir", "hangi"})  # fmt: skip
_ENGLISH_QUESTION = ("is", "are", "what", "which", "how", "did", "does", "do")


def names_home_device(command: str, language: AssistantLanguage) -> bool:
    words = folded(command).split()
    if any(word.startswith(_COMPUTER) for word in words):
        return False
    if language is AssistantLanguage.ENGLISH:
        return any(word in _ENGLISH_DEVICES for word in words) or _has_phrase(words, _ENGLISH_PHRASES)
    return any(word.startswith(_TURKISH_DEVICES) for word in words) or _has_phrase(words, _TURKISH_PHRASES)


def guards_the_house(command: str, language: AssistantLanguage) -> bool:
    """Changes a lock, the garage door or the alarm; asking whether the door is locked changes nothing."""
    words = folded(command).split()
    guards = _ENGLISH_GUARDS if language is AssistantLanguage.ENGLISH else _TURKISH_GUARDS
    return any(word.startswith(guards) for word in words) and not is_question(command, language)


def is_question(command: str, language: AssistantLanguage) -> bool:
    if command.rstrip().endswith("?"):
        return True
    if language is AssistantLanguage.ENGLISH:
        words = folded(command).split()
        return bool(words) and words[0] in _ENGLISH_QUESTION
    # The question particle is its own word ("kilitli mi"); folding would mix "mi" with "mı" anyway.
    return any(word.strip("?.,!") in _TURKISH_QUESTION for word in command.lower().split())


def _has_phrase(words: list[str], phrases: tuple[tuple[str, str], ...]) -> bool:
    pairs = list(zip(words, words[1:], strict=False))
    return any(first == a and second.startswith(b) for first, second in pairs for a, b in phrases)


def base_address(address: str) -> str | None:
    """ "http://homeassistant.local:8123/" → "http://homeassistant.local:8123"; None for anything that isn't a
    plain http(s) address (user names in it, a query, another scheme)."""
    parts = urlsplit(address.strip())
    if parts.scheme not in ("http", "https") or not parts.hostname or "@" in parts.netloc:
        return None
    if parts.query or parts.fragment:
        return None
    try:
        parts.port  # noqa: B018 - raises for a port that isn't a number
    except ValueError:
        return None
    return urlunsplit((parts.scheme, parts.netloc, parts.path.rstrip("/"), "", ""))


def conversation_request(text: str, language: AssistantLanguage) -> dict[str, str]:
    return {"text": text, "language": "en" if language is AssistantLanguage.ENGLISH else "tr"}


def spoken_reply(payload: Any) -> str | None:
    """response.speech.plain.speech from POST /api/conversation/process; None when the answer isn't shaped so."""
    if not isinstance(payload, dict):
        return None
    response = payload.get("response")
    speech = response.get("speech") if isinstance(response, dict) else None
    plain = speech.get("plain") if isinstance(speech, dict) else None
    said = plain.get("speech") if isinstance(plain, dict) else None
    return said.strip() if isinstance(said, str) else None
