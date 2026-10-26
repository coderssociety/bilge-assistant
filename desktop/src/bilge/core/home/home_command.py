"""Smart-home commands for Home Assistant: whether a command names a home device or room ("salonun ışığını aç",
"klimayı 22 dereceye ayarla", "kapı kilitli mi"), whether it acts on something that guards the house (a lock, the
garage door, the alarm, a door) and so needs a yes first, and what Home Assistant's conversation API sends back."""

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
_TURKISH_GUARDS = ("kilit", "kilid", "garaj", "alarm", "kapi")
_ENGLISH_GUARDS = ("lock", "unlock", "garage", "alarm", "door")
# Doing something to a guard, said any way ("açar mısın?", "can you unlock…?"): asked as a question it still acts.
_TURKISH_ACTION_WORDS = frozenset({"ac", "acin", "acsin", "kur", "kapa", "iptal", "devre", "devreye", "sustur"})
_TURKISH_ACTION_STEMS = ("acar", "acabil", "aciver", "acsana", "acmak", "acman", "acal", "kapat", "kilitle",
                         "kurar", "kurabil", "kursana", "kurman", "etkinlestir", "kaldir", "susturur", "coz")  # fmt: skip
# "kilitlendi mi", "kapatılmış mı", "kilit çözüldü mü": asking what happened, not asking for it.
_TURKISH_PASSIVE = ("kilitlen", "kapatil", "cozul")
# With their -ing forms: "how about unlocking the front door", "what about opening the garage".
_ENGLISH_ACTIONS = frozenset({"open", "close", "shut", "lock", "unlock", "arm", "disarm", "disable", "enable",
                              "activate", "deactivate", "raise", "lift", "lower", "turn", "switch", "silence",
                              "set", "opening", "closing", "shutting", "locking", "unlocking", "arming",
                              "disarming", "disabling", "enabling", "activating", "deactivating", "raising",
                              "lifting", "lowering", "turning", "switching", "silencing"})  # fmt: skip
# "is the garage door open": a state after "is", unless something is asked of Bilge ("is it possible to open…").
_ENGLISH_STATES = frozenset({"open", "shut", "lock"})
_ENGLISH_STATE_QUESTION = frozenset({"is", "are", "was", "were"})
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
    """Changes a lock, a door, the garage or the alarm, however politely it is asked; only asking how they are
    ("kapı kilitli mi", "is the front door locked") changes nothing."""
    words = folded(command).split()
    guards = _ENGLISH_GUARDS if language is AssistantLanguage.ENGLISH else _TURKISH_GUARDS
    if not any(word.startswith(guards) for word in words):
        return False
    return _names_an_action(words, language) or not is_question(command, language)


def _names_an_action(words: list[str], language: AssistantLanguage) -> bool:
    if language is AssistantLanguage.ENGLISH:
        actions = _ENGLISH_ACTIONS
        if words[0] in _ENGLISH_STATE_QUESTION and not {"to", "you"} & set(words):
            actions = actions - _ENGLISH_STATES
        return any(word in actions for word in words)
    return any(
        word in _TURKISH_ACTION_WORDS
        or (word.startswith(_TURKISH_ACTION_STEMS) and not word.startswith(_TURKISH_PASSIVE))
        for word in words
    )


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
