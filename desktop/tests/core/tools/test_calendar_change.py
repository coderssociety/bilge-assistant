from dataclasses import dataclass
from datetime import datetime

import pytest

from bilge.brain.agent import resolve
from bilge.core.language import AssistantLanguage
from bilge.core.tools import calendar_change
from bilge.core.tools.calendar_change import When

# A Thursday.
NOW = datetime(2026, 10, 15, 14, 5)
WEEK = 7 * 24 * 60


def turkish(said: str) -> calendar_change.Change:
    return calendar_change.parse(resolve(said, AssistantLanguage.TURKISH), NOW, english=False)


def english(said: str) -> calendar_change.Change:
    return calendar_change.parse(said, NOW, english=True)


@pytest.mark.parametrize(
    ("said", "event", "to", "shift"),
    [
        ("yarınki toplantıyı iptal et", When(1), When(), None),
        ("diş hekimi randevusunu cumaya al", When(), When(1), None),
        ("saat üçteki toplantıyı dörde ertele", When(None, (15, 0)), When(None, (16, 0)), None),
        ("yarınki toplantıyı cuma saat beşe al", When(1), When(1, (17, 0)), None),
        ("yarın saat üçte toplantıyı dörde al", When(1, (15, 0)), When(None, (16, 0)), None),
        ("toplantıyı yarın dörde al", When(), When(1, (16, 0)), None),
        ("toplantıyı yarından pazartesiye al", When(1), When(4), None),
        ("salıdaki toplantıyı perşembeye al", When(5), When(7), None),
        ("15 Kasım'daki toplantıyı 20 Kasım'a al", When(31), When(36), None),
        ("akşam yedideki yemeği sekize al", When(None, (19, 0)), When(None, (8, 0), either_half=True), None),
        ("toplantıyı bir saat ertele", When(), When(), 60),
        ("toplantıyı yarım saat öne al", When(), When(), -30),
        ("toplantıyı iki gün ertele", When(), When(), 2 * 24 * 60),
        ("toplantıyı haftaya al", When(), When(), WEEK),
        ("toplantıyı yarından sonraya al", When(), When(2), None),
    ],
)
def test_turkish_says_which_event_with_ki_and_where_it_goes_with_the_dative(said, event, to, shift):
    change = turkish(said)
    assert (change.event, change.to, change.shift_minutes, change.commanded) == (event, to, shift, True)


@pytest.mark.parametrize(
    ("said", "event", "to", "shift"),
    [
        ("cancel tomorrow's meeting", When(1), When(), None),
        ("move the dentist appointment to Friday", When(), When(1), None),
        ("reschedule the 3 o'clock meeting to 4", When(None, (15, 0)), When(None, (16, 0)), None),
        ("move the meeting from 3 to 4", When(None, (15, 0)), When(None, (16, 0)), None),
        ("move the standup to 9:30 tomorrow", When(), When(1, (9, 30)), None),
        ("move my 7pm dinner to 8", When(None, (19, 0)), When(None, (8, 0), either_half=True), None),
        ("push my 3pm meeting back an hour", When(None, (15, 0)), When(), 60),
        ("postpone tomorrow's meeting by a day", When(1), When(), 24 * 60),
        ("move the meeting an hour earlier", When(), When(), -60),
    ],
)
def test_english_says_where_the_event_goes_after_to(said, event, to, shift):
    change = english(said)
    assert (change.event, change.to, change.shift_minutes, change.commanded) == (event, to, shift, True)


def test_every_occurrence_only_when_said_and_answers_are_not_commands():
    assert turkish("salıdaki toplantının hepsini sil").every
    assert not turkish("salıdaki toplantıyı sil").every
    assert english("delete all occurrences of the standup").every
    # Answers to "which one?" leave the arguments to the model.
    assert not turkish("ikincisini al").commanded
    assert not turkish("saat beştekini").commanded
    assert not english("the second one").commanded


@dataclass(frozen=True)
class Event:
    title: str
    start: datetime
    all_day: bool = False


EVENTS = [
    Event("Ekip toplantısı", datetime(2026, 10, 15, 15, 0)),
    Event("Diş hekimi", datetime(2026, 10, 16, 10, 0)),
    Event("Bayram", datetime(2026, 10, 16), all_day=True),
    Event("Diş hekimi", datetime(2026, 10, 23, 10, 0)),
    Event("Proje toplantısı", datetime(2026, 10, 16, 15, 0)),
]


def titles(found):
    return [(e.title, e.start.day) for e in found]


def test_the_title_picks_the_event_and_without_a_day_the_nearest_one_counts():
    assert titles(calendar_change.matching(EVENTS, "diş hekimi", None, When(), False)) == [("Diş hekimi", 16)]
    day = datetime(2026, 10, 23).date()
    assert titles(calendar_change.matching(EVENTS, "berber", day, When(), False)) == []
    assert titles(calendar_change.matching(EVENTS, "diş hekimini", day, When(), False)) == [("Diş hekimi", 23)]


def test_generic_words_and_times_narrow_down_the_events():
    # "toplantıyı": both meetings fit, and the nearest day has one.
    assert titles(calendar_change.matching(EVENTS, "toplantıyı", None, When(), False)) == [("Ekip toplantısı", 15)]
    # Only a time: the generic word matches nothing at four, so the time alone decides.
    tomorrow = datetime(2026, 10, 16).date()
    found = calendar_change.matching(EVENTS, "randevu", tomorrow, When(None, (10, 0)), False)
    assert titles(found) == [("Diş hekimi", 16)]
    # "3'teki" may mean 03:00 or 15:00 when bare.
    assert titles(calendar_change.matching(EVENTS, "", tomorrow, When(None, (3, 0), True), False)) == [
        ("Proje toplantısı", 16)
    ]
    # All-day events have no time to match.
    assert titles(calendar_change.matching(EVENTS, "bayram", tomorrow, When(None, (0, 0)), False)) == []
    assert titles(calendar_change.matching(EVENTS, "", tomorrow, When(), False)) == titles(EVENTS[1:3] + EVENTS[4:])


def test_the_new_start_keeps_what_was_not_said():
    start = datetime(2026, 10, 16, 19, 0).astimezone()
    today = NOW.date()

    def moved(to=None, shift=None, all_day=False):
        change = calendar_change.Change(When(), to or When(), shift, False, True)
        found = calendar_change.new_start(start, all_day, change, today)
        return found.replace(tzinfo=None) if found else None

    assert moved(When(4)) == datetime(2026, 10, 19, 19, 0)
    assert moved(When(None, (8, 0), either_half=True)) == datetime(2026, 10, 16, 20, 0)
    assert moved(When(None, (8, 0))) == datetime(2026, 10, 16, 8, 0)
    assert moved(shift=-90) == datetime(2026, 10, 16, 17, 30)
    assert moved(When(4, (9, 0)), all_day=True) == datetime(2026, 10, 19)
    assert moved() is None
