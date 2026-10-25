"""Reads routine requests: "her gece 21'de hava durumunu söyle", "hafta içi her gün 7'de haberleri oku",
"every weekday at 7 read the news" (days, time and the command to run); "rutinlerim neler"; "akşam rutinini sil".

The schedule is the run of schedule words ending at the time ("hafta içi her gün 7'de"); everything else is the
command, run later exactly as if it had been said."""

import re
from collections.abc import Callable
from dataclasses import dataclass

from bilge.core.language import AssistantLanguage
from bilge.core.routines.routine_schedule import EVERY_DAY, WEEKDAYS, WEEKEND
from bilge.core.speech import turkish_number_parser, turkish_time_of_day
from bilge.core.text import folded
from bilge.core.tools import appointment_time, english_time_parser

MAX_COMMAND_CHARACTERS = 200


@dataclass(frozen=True)
class RoutineRequest:
    days: frozenset[int]
    hour: int
    minute: int
    command: str


@dataclass(frozen=True)
class Removal:
    # The words naming the routine ("akşam", "hava durumu"); empty when none were said.
    name: str
    every: bool = False


# Python weekdays; "cumartesi" before "cuma" and "pazartesi" before "pazar", which they start with.
_TURKISH_DAYS = (("pazartesi", 0), ("sali", 1), ("carsamba", 2), ("persembe", 3), ("cumartesi", 5), ("cuma", 4),
                 ("pazar", 6))  # fmt: skip
_TURKISH_SCHEDULE = frozenset(
    {"her", "gun", "gunu", "gunleri", "gunler", "sabah", "sabahlari", "aksam", "aksamlari", "gece", "geceleri",
     "ogle", "oglen", "ogleyin", "ogleden", "sonra", "hafta", "ici", "icleri", "sonu", "sonlari", "ve", "saat"}
)  # fmt: skip
_TURKISH_TIME = re.compile(
    r"(?<![^\W_])(?:saat\s+)?(?:\d{1,2}:\d{2}(?:'[^\W\d_]+)?|\d{1,2}(?:'[dt][ae]|\s+buçuk[^\W\d_]*))(?![^\W_])"
    r"|(?<![^\W_])saat\s+\d{1,2}(?![^\W_:])",
    re.IGNORECASE,
)
_BARE_SUFFIX = re.compile(r"(?<![\d:])(\d{1,2})([dt][ae])(?![^\W\d_])", re.IGNORECASE)
_ENGLISH_DAYS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
_ENGLISH_SCHEDULE = frozenset(
    {"every", "each", "day", "daily", "morning", "mornings", "evening", "evenings", "night", "nights", "afternoon",
     "afternoons", "weekday", "weekdays", "weekend", "weekends", "on", "and", "the"}
    | set(_ENGLISH_DAYS) | {f"{day}s" for day in _ENGLISH_DAYS}
)  # fmt: skip
_ENGLISH_HOURS = "one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve"
_PART_OF_DAY = r"(?:\s+in\s+the\s+(?:morning|afternoon|evening)|\s+at\s+night)?"
_ENGLISH_TIME = re.compile(
    r"\b(?:at\s+)?(?:\d{1,2}:\d{2}(?:\s*[ap]\.?\s*m\b\.?)?|\d{1,2}\s*[ap]\.?\s*m\b\.?|noon|midnight)" + _PART_OF_DAY
    + rf"|\bat\s+(?:\d{{1,2}}|{_ENGLISH_HOURS})\b(?:\s+o'?clock)?" + _PART_OF_DAY,
    re.IGNORECASE,
)  # fmt: skip
# "kapat" and "stop" end what runs now ("sabah rutinini durdur", "stop the music"); they never delete a routine.
_TURKISH_REMOVE = ("sil", "kaldir", "iptal")
_ENGLISH_REMOVE = frozenset({"delete", "remove", "cancel", "clear"})
# "rutini", "rutinlerimi", "routines": the routine itself; "rutin kontrol" uses the word as an adjective.
_TURKISH_ROUTINE = re.compile(r"rutin(?:ler)?(?:im(?:iz)?|in(?:iz)?)?(?:i|in|e|de|den)?")
_ENGLISH_ROUTINE = re.compile(r"routines?")
_ROUTINE_FILLER = frozenset({"lutfen", "hemen", "artik", "simdi", "please"})
# "bu hafta sonu", "next weekend": once, not a routine.
_ONE_OFF = frozenset({"bu", "gelecek", "onumuzdeki", "this", "next"})
_ALL = frozenset({"butun", "tum", "hepsini", "hepsi", "all", "every"})
_NAME_FILLER = frozenset({"bu", "su", "o", "benim", "the", "my", "a", "that", "this"})
_LIST_WORDS = {
    AssistantLanguage.TURKISH: frozenset({"neler", "ne", "nedir", "hangi", "hangileri", "listele", "say", "oku",
                                          "var", "goster", "soyle"}),
    AssistantLanguage.ENGLISH: frozenset({"what", "which", "list", "read", "tell", "show", "any", "have"}),
}  # fmt: skip


def parse(text: str, language: AssistantLanguage) -> RoutineRequest | None:
    """None unless the text says a repeating schedule, a time and something to do. A request that talks about
    the routine itself ("... bir rutin oluştur") is left to the model."""
    if _mentions_routine(text):
        return None
    if language is AssistantLanguage.ENGLISH:
        return _parse_english(text)
    return _parse_turkish(text)


def asks_for_list(text: str, language: AssistantLanguage) -> bool:
    words = folded(text).split()
    if _routine_at(words, language) is None or removal(text, language) is not None:
        return False
    return len(words) == 1 or any(word in _LIST_WORDS[language] for word in words)


def removal(text: str, language: AssistantLanguage) -> Removal | None:
    """Only a removal verb taking the routine as its object: "akşam rutinini sil", "delete the evening routine"."""
    words = folded(text).split()
    at = _routine_at(words, language)
    if at is None:
        return None
    if language is AssistantLanguage.ENGLISH:
        verb = next((i for i, word in enumerate(words[:at]) if word in _ENGLISH_REMOVE), None)
        if verb is None:
            return None
        named = words[verb + 1 : at]
    else:
        following = [word for word in words[at + 1 :] if word not in _ROUTINE_FILLER]
        if not following or not following[0].startswith(_TURKISH_REMOVE):
            return None
        named = words[:at]
    if any(word in _ALL for word in named) or (language is AssistantLanguage.TURKISH and words[at].startswith(
            ("rutinleri", "rutinlerin")) and not named):  # fmt: skip
        return Removal("", every=True)
    return Removal(" ".join(word for word in named if word not in _NAME_FILLER))


def _routine_at(words: list[str], language: AssistantLanguage) -> int | None:
    """Where the routine itself is named; a bare "rutin" before another word describes that word ("yarın rutin
    kontrolüm var mı")."""
    if language is AssistantLanguage.ENGLISH:
        return next((i for i, word in enumerate(words) if _ENGLISH_ROUTINE.fullmatch(word)), None)
    for i, word in enumerate(words):
        if not _TURKISH_ROUTINE.fullmatch(word):
            continue
        if word != "rutin" or i + 1 == len(words) or words[i + 1] in _LIST_WORDS[language]:
            return i
    return None


def _mentions_routine(text: str) -> bool:
    return any(_is_routine_word(word) for word in folded(text).split())


def _is_routine_word(word: str) -> bool:
    return word.startswith("rutin") or word.startswith("routine")


def _parse_turkish(text: str) -> RoutineRequest | None:
    resolved = turkish_time_of_day.resolve(turkish_number_parser.digitize(_BARE_SUFFIX.sub(r"\1'\2", text)))
    match = _TURKISH_TIME.search(resolved)
    if match is None:
        return None
    before = resolved[: match.start()].split()
    taken = _schedule_tail(before, lambda word: folded(word) in _TURKISH_SCHEDULE or _turkish_day(word) is not None)
    schedule = [folded(word) for word in before[len(before) - taken :]]
    if taken < len(before) and folded(before[-taken - 1]) in _ONE_OFF:
        return None
    days = _turkish_days(schedule)
    clock = appointment_time.clock(" ".join([*before[len(before) - taken :], match.group(0)]))
    if days is None or clock is None:
        return None
    return _request(days, clock, [*before[: len(before) - taken], *resolved[match.end() :].split()], {"ve"})


def _turkish_day(word: str) -> int | None:
    plain = folded(word)
    return next((day for stem, day in _TURKISH_DAYS if plain.startswith(stem) and len(plain) - len(stem) <= 5), None)


def _turkish_days(schedule: list[str]) -> frozenset[int] | None:
    named = frozenset(day for word in schedule if (day := _turkish_day(word)) is not None)
    repeating = "her" in schedule or any(word.endswith(("leri", "lari")) for word in schedule)
    if named:
        return named if repeating else None
    if not repeating:
        return None
    if "hafta" in schedule and ("ici" in schedule or "icleri" in schedule):
        return WEEKDAYS
    if "hafta" in schedule and ("sonu" in schedule or "sonlari" in schedule):
        return WEEKEND
    return EVERY_DAY


def _parse_english(text: str) -> RoutineRequest | None:
    match = _ENGLISH_TIME.search(text)
    if match is None:
        return None
    before, after = text[: match.start()].split(), text[match.end() :].split()
    taken = _schedule_tail(before, lambda word: _english_word(word) in _ENGLISH_SCHEDULE)
    # "at 7 every weekday, read the news": the schedule may also follow the time.
    following = 0
    if after and _english_word(after[0]) in {"every", "each", "on", "daily"}:
        following = _schedule_tail(after, lambda word: _english_word(word) in _ENGLISH_SCHEDULE,
                                   from_start=True)  # fmt: skip
    schedule_words = [*before[len(before) - taken :], *after[:following]]
    if taken < len(before) and _english_word(before[-taken - 1]) in _ONE_OFF:
        return None
    days = _english_days([_english_word(word) for word in schedule_words])
    parsed = english_time_parser.parse(" ".join([*schedule_words, match.group(0)]))
    if days is None or parsed is None or parsed.hour is None:
        return None
    return _request(days, (parsed.hour, parsed.minute or 0), [*before[: len(before) - taken], *after[following:]],
                    {"and", "please", "then"})  # fmt: skip


def _english_word(word: str) -> str:
    return word.strip(",.;:!?").lower()


def _english_days(schedule: list[str]) -> frozenset[int] | None:
    named = frozenset(i for i, day in enumerate(_ENGLISH_DAYS) for word in schedule if word in (day, f"{day}s"))
    repeating = bool({"every", "each", "daily"} & set(schedule)) or any(
        word.endswith("s") and word.rstrip("s") in {*_ENGLISH_DAYS, "morning", "evening", "night", "afternoon"}
        for word in schedule
    )
    if named:
        return named if repeating else None
    if not repeating and not {"weekdays", "weekends"} & set(schedule):
        return None
    if {"weekday", "weekdays"} & set(schedule):
        return WEEKDAYS
    if {"weekend", "weekends"} & set(schedule):
        return WEEKEND
    return EVERY_DAY


def _schedule_tail(words: list[str], is_schedule: Callable[[str], bool], from_start: bool = False) -> int:
    """How many words at the end of `words` (at the start with `from_start`) belong to the schedule."""
    count = 0
    for word in words if from_start else reversed(words):
        if not is_schedule(word):
            break
        count += 1
    return count


def _request(days: frozenset[int], clock: tuple[int, int], rest: list[str], edges: set[str]) -> RoutineRequest | None:
    words = " ".join(rest).strip(" ,.;:").split()
    while words and folded(words[0]).strip(",") in edges:
        words = words[1:]
    while words and folded(words[-1]).strip(",") in edges:
        words = words[:-1]
    command = " ".join(words).strip(" ,.;:")
    if not command or len(command) > MAX_COMMAND_CHARACTERS:
        return None
    return RoutineRequest(days, clock[0], clock[1], command)
