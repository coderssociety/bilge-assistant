"""What a spoken change to the calendar asks for and which event it means: "yarınki toplantıyı iptal et", "diş hekimi
randevusunu cumaya al", "saat 3'teki toplantıyı 4'e ertele", "move tomorrow's meeting to Friday at 4". Turkish
commands have already been through turkish_number_parser and turkish_time_of_day ("dörde" → "4'e").

In Turkish the dative names where the event goes ("cumaya", "4'e", "yarına"), the ablative or "-ki" where it is now
("3'ten", "yarınki", "salıdaki"); in English the part after "to" is the new time."""

import re
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from typing import Protocol

from bilge.core.text import folded, lowercased
from bilge.core.tools import (
    appointment_time,
    english_time_parser,
    phrase_matcher,
    relative_day_parser,
    timer_phrase_parser,
)

MINUTES_IN_DAY = 24 * 60
DAYS_IN_WEEK = 7
_HALF_DAY = 12

_TURKISH_DELETE = ("sil", "iptal", "kaldir")
_TURKISH_MOVE = ("ertele", "tasi", "kaydir", "degistir", "aktar")
_TURKISH_MOVE_WORDS = frozenset({"al", "alir", "alabilir", "alsana", "cek", "getir"})
_ENGLISH_VERBS = frozenset({"delete", "remove", "cancel", "move", "reschedule", "postpone", "push", "shift", "delay",
                            "change", "bring"})  # fmt: skip
_TURKISH_EVERY = frozenset({"hepsini", "hepsi", "hepsinin", "tumunu", "tumu", "butun", "tum", "tumden"})
_ENGLISH_EVERY = frozenset({"all", "every", "series", "occurrences"})
_TURKISH_EARLIER = ("erken", "geri")
_ENGLISH_EARLIER = frozenset({"earlier", "forward"})
_TURKISH_PARTS_OF_DAY = ("sabah", "aksam", "ogle", "gece")
_TURKISH_TIME_WORDS = ("saat", "bucu", "yarin", "bugun", "obur", "ertesi", "hafta", "sabah", "aksam", "ogle", "gece",
                       "gun", "dakika", "sonra", "yarim", "ayin")  # fmt: skip
_MONTHS = ("ocak", "subat", "mart", "nisan", "mayis", "haziran", "temmuz", "agustos", "eylul", "ekim", "kasim",
           "aralik")  # fmt: skip
_TURKISH_DATIVES = frozenset({"yarina", "bugune", "haftaya", "sonraya", "sabaha", "aksama", "ogleye", "geceye",
                              "bucuga"})  # fmt: skip
_KI_ENDINGS = ("daki", "deki", "taki", "teki")
_ABLATIVE_ENDINGS = ("dan", "den", "tan", "ten")
_NUMBER_DATIVE = re.compile(r"^\d{1,2}(?::\d{2})?['’]y?[ae]$")
_NUMBER_ABLATIVE = re.compile(r"^\d{1,2}(?::\d{2})?['’][dt][ae]n$")
_NAME_DATIVE = re.compile(r"^[^\W\d_]+['’]y?[ae]$")
_SUFFIXED_HOUR = re.compile(r"(?<![\d:])(\d{1,2})['’](?:[dt][ae](?:ki|n)?|y?[ae])(?![^\W\d_])")
_TWO_DIGIT_CLOCK = re.compile(r"(?<!\d)\d{2}:\d{2}")
_DAYS = re.compile(r"\b(\d+) (?:gun|days?)\b")
_WEEKS = re.compile(r"\b(\d+) (?:hafta|weeks?)\b")
_ENGLISH_O_CLOCK = re.compile(r"\b(\d{1,2})\s*o['’]?\s*clock\b")
_ENGLISH_FROM = re.compile(r"\bfrom\s+(\d{1,2})\b(?!\s*:)")
_ENGLISH_BARE_TARGET = re.compile(r"^\s*(?:at\s+)?(\d{1,2}(?::\d{2})?)\b(?!\s*(?:minutes?|hours?|days?|weeks?))")
_ENGLISH_TO = re.compile(r"\bto\b")
_MERIDIEM = re.compile(r"\d\s*[ap]\.?\s*m\b")
_ENGLISH_A_DAY = re.compile(r"\b(?:a|one) (day|week)\b")
_ENGLISH_DURATION = re.compile(
    r"\b(?:half an|an?|one|two|three|four|five|ten|fifteen|twenty|thirty|forty five|\d+)\s+(?:hours?|minutes?)"
    r"(?:\s+and\s+a\s+half)?"
)
_TURKISH_GENERIC = ("toplanti", "randevu", "etkinli", "gorusme", "takvim", "plan")
_ENGLISH_GENERIC = frozenset({"meeting", "meetings", "appointment", "appointments", "event", "events", "calendar"})


@dataclass(frozen=True)
class When:
    # Days from today.
    day: int | None = None
    clock: tuple[int, int] | None = None
    # A bare hour ("4'e", "to 8") that may be either half of the day; the one nearer the event's own time is taken.
    either_half: bool = False

    @property
    def said(self) -> bool:
        return self.day is not None or self.clock is not None


@dataclass(frozen=True)
class Change:
    event: When
    to: When
    shift_minutes: int | None
    every: bool
    # The command itself asks for the change, so its words decide; an answer such as "ikincisi" leaves it to the model.
    commanded: bool


def parse(command: str, now: datetime, english: bool) -> Change:
    return _english(command, now) if english else _turkish(command, now)


# MARK: - Turkish


def _turkish(command: str, now: datetime) -> Change:
    words = command.split()
    folds = [folded(word).replace(" ", "") for word in words]
    strong = any(fold.startswith(_TURKISH_DELETE + _TURKISH_MOVE) for fold in folds)
    # "al", "çek" are a move only with a new time: "cumaya al", not "ikincisini al".
    weak = any(fold in _TURKISH_MOVE_WORDS for fold in folds)
    moving = weak or any(fold.startswith(_TURKISH_MOVE) for fold in folds)
    source: list[str] = []
    target: list[str] = []
    shift: int | None = None
    for run in _runs(words, folds):
        for part, is_source in _split_at_ablative(run):
            text = " ".join(word for word, _ in part)
            minutes = _turkish_shift(part, text) if moving else None
            if minutes is not None:
                shift = minutes
            elif moving and not is_source and _is_dative(*part[-1]):
                target.extend(word for word, _ in part)
            else:
                source.extend(word for word, _ in part)
    if shift is not None and any(fold == "one" or fold.startswith(_TURKISH_EARLIER) for fold in folds):
        shift = -shift
    commanded = strong or (weak and (bool(target) or shift is not None))
    return Change(_turkish_when(source, now), _turkish_when(target, now), shift,
                  any(fold in _TURKISH_EVERY for fold in folds), commanded)  # fmt: skip


def _is_turkish_verb(fold: str) -> bool:
    return fold.startswith(_TURKISH_DELETE + _TURKISH_MOVE) or fold in _TURKISH_MOVE_WORDS


def _is_time_word(word: str, fold: str) -> bool:
    if any(character.isdigit() for character in word):
        return True
    return (
        fold.startswith(_TURKISH_TIME_WORDS)
        or fold.startswith(_MONTHS)
        or relative_day_parser.weekday_of(_without_ki(fold)) is not None
    )


def _runs(words: list[str], folds: list[str]) -> list[list[tuple[str, str]]]:
    """Words about time that stand together: "cuma saat 5'e", "yarınki", "1 saat"."""
    runs: list[list[tuple[str, str]]] = []
    current: list[tuple[str, str]] = []
    for word, fold in zip(words, folds, strict=True):
        if _is_time_word(word, fold):
            current.append((word, fold))
        elif current:
            runs.append(current)
            current = []
    if current:
        runs.append(current)
    return runs


def _split_at_ablative(run: list[tuple[str, str]]) -> list[tuple[list[tuple[str, str]], bool]]:
    """ "yarından cumaya" is from tomorrow to Friday; "yarından sonra" is one day."""
    for index, (word, fold) in enumerate(run[:-1]):
        following = run[index + 1][1]
        if _is_ablative(word, fold) and not following.startswith("sonra"):
            return [(run[: index + 1], True), (run[index + 1 :], False)]
    return [(run, False)]


def _is_dative(word: str, fold: str) -> bool:
    if _NUMBER_DATIVE.match(word) or fold in _TURKISH_DATIVES:
        return True
    if fold.endswith(("ya", "ye")) and relative_day_parser.weekday_of(fold) is not None:
        return True
    return bool(_NAME_DATIVE.match(word)) and fold.startswith(_MONTHS)


def _is_ablative(word: str, fold: str) -> bool:
    if _NUMBER_ABLATIVE.match(word):
        return True
    if not fold.endswith(_ABLATIVE_ENDINGS):
        return False
    return relative_day_parser.weekday_of(fold) is not None or fold.startswith(("yarin", "bugun", *_MONTHS))


def _without_ki(fold: str) -> str:
    """ "salıdaki" → "sali", which the day parser knows."""
    for ending in _KI_ENDINGS:
        stem = fold[: -len(ending)]
        if fold.endswith(ending) and relative_day_parser.weekday_of(stem) is not None:
            return stem
    return fold


def _turkish_shift(part: list[tuple[str, str]], text: str) -> int | None:
    """ "1 saat", "yarım saat sonraya", "2 gün", "haftaya" (as a move: a week later)."""
    folds = [fold for _, fold in part]
    if folds == ["haftaya"]:
        return DAYS_IN_WEEK * MINUTES_IN_DAY
    if _turkish_clock(text) is not None:
        return None
    joined = " ".join(folds)
    for pattern, days in ((_DAYS, 1), (_WEEKS, DAYS_IN_WEEK)):
        found = pattern.search(joined)
        if found is not None:
            return int(found.group(1)) * days * MINUTES_IN_DAY
    if any(fold.startswith(("saat", "dakika")) for fold in folds):
        parsed = timer_phrase_parser.parse(text)
        if parsed is not None and parsed.duration_seconds:
            return parsed.duration_seconds // 60
    return None


def _turkish_clock(text: str) -> tuple[int, int] | None:
    def hour(match: re.Match) -> str:
        said_with_saat = lowercased(text[: match.start()]).rstrip().endswith("saat")
        return match.group(1) if said_with_saat else f"saat {match.group(1)}"

    return appointment_time.clock(_SUFFIXED_HOUR.sub(hour, text.replace("buçuğ", "buçuk")))


def _turkish_when(words: list[str], now: datetime) -> When:
    if not words:
        return When()
    text = " ".join(words)
    day_text = " ".join(_without_ki(folded(word).replace(" ", "")) for word in words)
    clock = _turkish_clock(text)
    either_half = (
        clock is not None
        and clock[0] < _HALF_DAY
        and not _TWO_DIGIT_CLOCK.search(text)
        and not any(part in folded(text) for part in _TURKISH_PARTS_OF_DAY)
    )
    return When(relative_day_parser.day_offset(day_text, now), clock, either_half)


# MARK: - English


def _english(command: str, now: datetime) -> Change:
    lowered = lowercased(command)
    words = re.findall(r"[a-z]+", lowered)
    commanded = any(word in _ENGLISH_VERBS for word in words)
    moving = commanded and not any(word in ("delete", "remove", "cancel") for word in words)
    source, target = lowered, ""
    splits = list(_ENGLISH_TO.finditer(lowered)) if moving else []
    if splits:
        last = splits[-1]
        candidate = lowered[last.end() :]
        if _english_when(candidate, now, target=True).said:
            source, target = lowered[: last.start()], candidate
    shift = _english_shift(target or (lowered if moving else ""))
    if shift is not None and any(word in _ENGLISH_EARLIER for word in words):
        shift = -shift
    event = _english_when(source if shift is None or target else _without_duration(source), now, target=False)
    return Change(event, _english_when(target, now, target=True) if shift is None else When(), shift,
                  any(word in _ENGLISH_EVERY for word in words), commanded)  # fmt: skip


def _english_when(text: str, now: datetime, target: bool) -> When:
    if not text.strip():
        return When()
    text = _ENGLISH_FROM.sub(r"at \1", _ENGLISH_O_CLOCK.sub(r"at \1", text))
    if target:
        text = _ENGLISH_BARE_TARGET.sub(r"at \1", text)
    parsed = english_time_parser.parse(text)
    clock = (parsed.hour, parsed.minute or 0) if parsed is not None and parsed.hour is not None else None
    either_half = (
        clock is not None
        and clock[0] < _HALF_DAY
        and not _MERIDIEM.search(text)
        and ":" not in text
        and not any(word in english_time_parser.PART_OF_DAY_WORDS for word in text.split())
    )
    return When(english_time_parser.day_offset(text, now), clock, either_half)


def _english_shift(text: str) -> int | None:
    if not text:
        return None
    for pattern, days in ((_DAYS, 1), (_WEEKS, DAYS_IN_WEEK)):
        found = pattern.search(text)
        if found is not None:
            return int(found.group(1)) * days * MINUTES_IN_DAY
    single = _ENGLISH_A_DAY.search(text)
    if single is not None:
        return (DAYS_IN_WEEK if single.group(1) == "week" else 1) * MINUTES_IN_DAY
    seconds = 0
    for phrase in _ENGLISH_DURATION.findall(text):
        parsed = english_time_parser.parse(phrase)
        seconds += (parsed.duration_seconds or 0) if parsed is not None else 0
    return seconds // 60 or None


def _without_duration(text: str) -> str:
    return _ENGLISH_DURATION.sub(" ", _ENGLISH_A_DAY.sub(" ", _DAYS.sub(" ", text)))


# MARK: - Finding the event


class Dated(Protocol):
    title: str
    start: datetime
    all_day: bool


def matching[Event: Dated](
    events: Sequence[Event], title: str, day: date | None, when: When, english: bool
) -> list[Event]:
    """The events a change means: on the day and at the time said, with the title said. Without a day, only the
    nearest day with such an event counts, so "the dentist" is the next appointment, not every one this month."""
    timed = [e for e in events if (day is None or e.start.date() == day) and _at(e, when)]
    specific, generic = _title_words(title, english)
    found = _best_titles(timed, specific) if specific else []
    if not specific:
        found = (_best_titles(timed, generic) if generic else []) or timed
    if day is None and found:
        nearest = min(e.start.date() for e in found)
        found = [e for e in found if e.start.date() == nearest]
    return found


def _at(event: Dated, when: When) -> bool:
    if when.clock is None:
        return True
    if event.all_day:
        return False
    hour, minute = when.clock
    hours = {hour, (hour + _HALF_DAY) % 24, (hour - _HALF_DAY) % 24} if when.either_half else {hour}
    return event.start.minute == minute and event.start.hour in hours


def _title_words(title: str, english: bool) -> tuple[str, str]:
    """(the title's own words, the generic ones such as "toplantı"), without words about time or the change."""
    specific, generic = [], []
    for word in title.split():
        fold = folded(word).replace(" ", "")
        if not fold or _is_time_word(word, fold) or _is_turkish_verb(fold) or fold in _ENGLISH_VERBS:
            continue
        if (fold in _ENGLISH_GENERIC) if english else fold.startswith(_TURKISH_GENERIC):
            generic.append(word)
        elif not english or not english_time_parser.day_offset(word, datetime(2000, 1, 3)):
            specific.append(word)
    return " ".join(specific), " ".join(generic)


def _best_titles[Event: Dated](events: Sequence[Event], query: str) -> list[Event]:
    scored = [(phrase_matcher.score(query, event.title), event) for event in events]
    best = max((score for score, _ in scored), default=0.0)
    if best < phrase_matcher.MINIMUM_SCORE:
        return []
    return [event for score, event in scored if score == best]


def new_start(start: datetime, all_day: bool, change: Change, today: date) -> datetime | None:
    """When the event begins after the change, in local time; None when the command gives no new time."""
    if change.shift_minutes:
        # Wall-clock arithmetic, so "one day later" stays at the same hour across a change to summer time.
        return (start.replace(tzinfo=None) + timedelta(minutes=change.shift_minutes)).astimezone()
    to = change.to
    if not to.said:
        return None
    day = today + timedelta(days=to.day) if to.day is not None else start.date()
    if all_day:
        return datetime.combine(day, time()).astimezone()
    hour, minute = to.clock or (start.hour, start.minute)
    if to.clock is not None and to.either_half and hour < _HALF_DAY:
        hour = min((hour, hour + _HALF_DAY), key=lambda candidate: abs(candidate - start.hour))
    return datetime.combine(day, time(hour, minute)).astimezone()
