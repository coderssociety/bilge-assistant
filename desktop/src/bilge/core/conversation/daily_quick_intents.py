"""Fast-path rules for unit conversions, world time, brightness, Do Not Disturb, Bluetooth, power and playback. Same
contract as quick_intent_parser: exact, narrow phrasings only; everything else goes to the model."""

from collections.abc import Callable
from dataclasses import dataclass
from enum import StrEnum

from bilge.core.tools import unit_conversion, world_clock


class LevelAction(StrEnum):
    SET = "set"
    INCREASE = "increase"
    DECREASE = "decrease"


class Switch(StrEnum):
    ON = "on"
    OFF = "off"
    STATUS = "status"


class PowerAction(StrEnum):
    RESTART = "restart"
    SHUT_DOWN = "shutDown"
    LOG_OUT = "logOut"


class PlaybackAction(StrEnum):
    SEEK = "seek"
    RESTART_TRACK = "restartTrack"
    SHUFFLE_ON = "shuffleOn"
    SHUFFLE_OFF = "shuffleOff"
    REPEAT_TRACK = "repeatTrack"
    REPEAT_ALL = "repeatAll"
    REPEAT_OFF = "repeatOff"


@dataclass(frozen=True)
class ConvertUnits:
    # As the convertUnits tool takes them: "5 foot 10 inch", "centimeter".
    quantity: str
    to: str


@dataclass(frozen=True)
class WorldClock:
    place: str
    other: str = ""
    difference: bool = False


@dataclass(frozen=True)
class Brightness:
    action: LevelAction
    amount: int | None = None


@dataclass(frozen=True)
class DoNotDisturb:
    action: Switch


@dataclass(frozen=True)
class Bluetooth:
    action: Switch


@dataclass(frozen=True)
class Power:
    action: PowerAction


@dataclass(frozen=True)
class Playback:
    action: PlaybackAction
    # Only for SEEK; negative goes back.
    seconds: int = 0


DailyIntent = ConvertUnits | WorldClock | Brightness | DoNotDisturb | Bluetooth | Power | Playback


def parse(w: list[str], text: str) -> DailyIntent | None:
    """`w` are the folded, simplified words; `text` the digitized command the conversion and clock parsers read."""
    rules: tuple[Callable[[list[str]], DailyIntent | None], ...] = (
        _brightness, _do_not_disturb, _bluetooth, _power, _playback,
    )  # fmt: skip
    for rule in rules:
        intent = rule(w)
        if intent is not None:
            return intent
    conversion = unit_conversion.parse(text)
    if conversion is not None:
        return ConvertUnits(unit_conversion.canonical(conversion.quantities), conversion.target.key)
    clock = world_clock.parse(text)
    if clock is not None:
        other = clock.places[1].english if len(clock.places) > 1 else ""
        return WorldClock(clock.places[0].english, other, clock.difference)
    return None


# Brightness

_BRIGHTNESS_SUBJECTS = (["parlakligi"], ["ekran", "parlakligini"], ["ekranin", "parlakligini"])
_UP_VERBS = frozenset({"artir", "arttir", "yukselt", "ac"})
_DOWN_VERBS = frozenset({"azalt", "dusur", "kis", "alcalt"})
_SET_VERBS = frozenset({"yap", "getir", "ayarla", "cek", "cikar", "indir", "dusur"})
# With a bare number these change it by that much ("20 düşür"); with a dative ending they set it ("20'ye düşür").
_BY_OR_SET_VERBS = {"indir": False, "dusur": False, "cikar": True}
_FULL_BRIGHTNESS = (["en", "yuksege", "cikar"], ["sonuna", "kadar", "ac"], ["sonuna", "kadar", "artir"])
_SCREEN_PHRASES = {
    ("ekrani", "karart"): LevelAction.DECREASE, ("ekrani", "aydinlat"): LevelAction.INCREASE,
    ("ekrani", "parlaklastir"): LevelAction.INCREASE,
}  # fmt: skip
_MAX_LEVEL = 100


def _brightness(w: list[str]) -> Brightness | None:
    phrase = _SCREEN_PHRASES.get(tuple(w))
    if phrase is not None:
        return Brightness(phrase)
    rest = next((w[len(s) :] for s in _BRIGHTNESS_SUBJECTS if w[: len(s)] == s and len(w) > len(s)), None)
    if rest is None or len(rest) > 3:
        return None
    if rest in _FULL_BRIGHTNESS:
        return Brightness(LevelAction.SET, _MAX_LEVEL)
    verb, before = rest[-1], rest[:-1]
    if before in ([], ["biraz"]):
        if verb in _UP_VERBS:
            return Brightness(LevelAction.INCREASE)
        return Brightness(LevelAction.DECREASE) if verb in _DOWN_VERBS else None
    if not before or not all(word == "yuzde" or _leading_number(word) is not None for word in before):
        return None
    number_word = before[-1]
    level = _leading_number(number_word)
    if level is None:
        return None
    level, bare = min(level, _MAX_LEVEL), number_word.isdigit()
    if verb in _BY_OR_SET_VERBS and bare:
        return Brightness(LevelAction.INCREASE if _BY_OR_SET_VERBS[verb] else LevelAction.DECREASE, level)
    if verb in _UP_VERBS - {"ac"} and bare:
        return Brightness(LevelAction.INCREASE, level)
    if verb in _DOWN_VERBS and bare:
        return Brightness(LevelAction.DECREASE, level)
    return Brightness(LevelAction.SET, level) if verb in _SET_VERBS else None


# Do Not Disturb

_DND_SUBJECTS = (
    ["rahatsiz", "etmeyin"], ["rahatsiz", "etmeyini"], ["rahatsiz", "etme"], ["rahatsiz", "etmeyi"],
    ["rahatsiz", "etmeyin", "modunu"], ["rahatsiz", "etme", "modunu"], ["rahatsiz", "etmeyin", "modu"],
    ["rahatsiz", "etme", "modu"], ["odak", "modunu"], ["odak", "modu"],
)  # fmt: skip
_SWITCH_ENDINGS = {
    ("ac",): Switch.ON, ("kapat",): Switch.OFF, ("acik", "mi"): Switch.STATUS,
    ("acik", "mi", "kapali", "mi"): Switch.STATUS,
}  # fmt: skip
_NOTIFICATION_PHRASES = {
    ("bildirimleri", "sessize", "al"): Switch.ON, ("bildirimleri", "sustur"): Switch.ON,
    ("bildirimleri", "kapat"): Switch.ON, ("bildirimleri", "ac"): Switch.OFF,
}  # fmt: skip


def _do_not_disturb(w: list[str]) -> DoNotDisturb | None:
    phrase = _NOTIFICATION_PHRASES.get(tuple(w))
    if phrase is not None:
        return DoNotDisturb(phrase)
    for subject in _DND_SUBJECTS:
        if w[: len(subject)] == subject:
            ending = _SWITCH_ENDINGS.get(tuple(w[len(subject) :]))
            if ending is not None:
                return DoNotDisturb(ending)
    return None


# Bluetooth

_BLUETOOTH_SUBJECTS = ("bluetooth", "bluetoothu", "blutut", "blututu", "bluetuth", "bluetuthu")
_BLUETOOTH_ENDINGS = {
    "ac": Switch.ON, "kapat": Switch.OFF, "acikmi": Switch.STATUS, "acikmikapalimi": Switch.STATUS,
    "durumu": Switch.STATUS, "durumune": Switch.STATUS,
}  # fmt: skip


def _bluetooth(w: list[str]) -> Bluetooth | None:
    """ "Bluetooth'u" folds to "bluetoothu", so the words are compared without spaces."""
    compact = "".join(w)
    for subject in _BLUETOOTH_SUBJECTS:
        ending = _BLUETOOTH_ENDINGS.get(compact.removeprefix(subject)) if compact.startswith(subject) else None
        if ending is not None:
            return Bluetooth(ending)
    return None


# Power

_POWER_PHRASES: dict[tuple[str, ...], PowerAction] = {
    ("yeniden", "baslat"): PowerAction.RESTART, ("bilgisayari", "yeniden", "baslat"): PowerAction.RESTART,
    ("sistemi", "yeniden", "baslat"): PowerAction.RESTART, ("bilgisayari", "restart", "et"): PowerAction.RESTART,
    ("restart", "at"): PowerAction.RESTART, ("bilgisayari", "kapat"): PowerAction.SHUT_DOWN,
    ("sistemi", "kapat"): PowerAction.SHUT_DOWN, ("oturumu", "kapat"): PowerAction.LOG_OUT,
    ("oturumdan", "cik"): PowerAction.LOG_OUT, ("oturumu", "sonlandir"): PowerAction.LOG_OUT,
}  # fmt: skip


def _power(w: list[str]) -> Power | None:
    action = _POWER_PHRASES.get(tuple(w))
    return Power(action) if action is not None else None


# Playback

_MEDIA_OBJECTS = frozenset({"sarkiyi", "muzigi", "videoyu", "parcayi"})
_SEEK_DIRECTIONS = {"ileri": 1, "geri": -1}
_SEEK_VERBS = frozenset({"sar", "al"})
_TIME_UNITS = {"saniye": 1, "dakika": 60}
_HALF_MINUTE = 30
DEFAULT_SEEK_SECONDS = 10
# Bare ones are only about a track; the rest need "şarkıyı" or the like ("baştan başlat" alone could be anything).
_RESTART_BARE = (["basa", "sar"], ["bastan", "cal"], ["en", "basa", "sar"], ["parcanin", "basina", "don"])
_RESTART_WITH_OBJECT = (["bastan", "baslat"], ["yeniden", "baslat"], ["bastan", "al"], ["basa", "al"])
_PLAYBACK_PHRASES: dict[tuple[str, ...], PlaybackAction] = {
    ("karisik", "cal"): PlaybackAction.SHUFFLE_ON, ("rastgele", "cal"): PlaybackAction.SHUFFLE_ON,
    ("sarkilari", "karistir"): PlaybackAction.SHUFFLE_ON, ("listeyi", "karistir"): PlaybackAction.SHUFFLE_ON,
    ("karisik", "calmayi", "ac"): PlaybackAction.SHUFFLE_ON, ("karistirmayi", "ac"): PlaybackAction.SHUFFLE_ON,
    ("karisik", "calmaya", "gec"): PlaybackAction.SHUFFLE_ON,
    ("karisik", "calmayi", "kapat"): PlaybackAction.SHUFFLE_OFF, ("karistirmayi", "kapat"): PlaybackAction.SHUFFLE_OFF,
    ("sirayla", "cal"): PlaybackAction.SHUFFLE_OFF,
    ("bu", "sarkiyi", "tekrarla"): PlaybackAction.REPEAT_TRACK, ("sarkiyi", "tekrarla"): PlaybackAction.REPEAT_TRACK,
    ("bu", "parcayi", "tekrarla"): PlaybackAction.REPEAT_TRACK, ("parcayi", "tekrarla"): PlaybackAction.REPEAT_TRACK,
    ("listeyi", "tekrarla"): PlaybackAction.REPEAT_ALL, ("calma", "listesini", "tekrarla"): PlaybackAction.REPEAT_ALL,
    ("hepsini", "tekrarla"): PlaybackAction.REPEAT_ALL, ("albumu", "tekrarla"): PlaybackAction.REPEAT_ALL,
    ("tekrarlamayi", "ac"): PlaybackAction.REPEAT_ALL,
    ("tekrari", "kapat"): PlaybackAction.REPEAT_OFF, ("tekrarlamayi", "kapat"): PlaybackAction.REPEAT_OFF,
    ("tekrarlamayi", "durdur"): PlaybackAction.REPEAT_OFF, ("tekrar", "modunu", "kapat"): PlaybackAction.REPEAT_OFF,
}  # fmt: skip


def _playback(w: list[str]) -> Playback | None:
    action = _PLAYBACK_PHRASES.get(tuple(w))
    if action is not None:
        return Playback(action)
    has_object = bool(w) and w[0] in _MEDIA_OBJECTS
    body = w[1:] if has_object else w
    if body in _RESTART_BARE or (has_object and body in _RESTART_WITH_OBJECT):
        return Playback(PlaybackAction.RESTART_TRACK)
    return _seek(body)


def _seek(w: list[str]) -> Playback | None:
    """ "30 saniye ileri sar", "1 dakika geri al", "biraz ileri sar", "10 saniye atla"."""
    if len(w) >= 2 and w[-1] == "atla":
        seconds = _duration(w[:-1])
        return Playback(PlaybackAction.SEEK, seconds) if seconds else None
    if len(w) < 2 or w[-1] not in _SEEK_VERBS or w[-2] not in _SEEK_DIRECTIONS:
        return None
    amount = w[:-2]
    seconds = DEFAULT_SEEK_SECONDS if amount in ([], ["biraz"]) else _duration(amount)
    return Playback(PlaybackAction.SEEK, seconds * _SEEK_DIRECTIONS[w[-2]]) if seconds else None


def _duration(words: list[str]) -> int | None:
    """ "30 saniye", "1 dakika 30 saniye", "yarım dakika"."""
    if words == ["yarim", "dakika"]:
        return _HALF_MINUTE
    if not words or len(words) % 2:
        return None
    total = 0
    for number, unit in zip(words[::2], words[1::2], strict=True):
        if not number.isdigit() or unit not in _TIME_UNITS:
            return None
        total += int(number) * _TIME_UNITS[unit]
    return total or None


def _leading_number(word: str) -> int | None:
    digits = ""
    for ch in word:
        if not ch.isdigit():
            break
        digits += ch
    return int(digits) if digits and digits.isascii() else None
