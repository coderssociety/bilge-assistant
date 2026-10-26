from datetime import datetime

import pytest

from bilge.core.tools import english_time_parser

THURSDAY = datetime(2026, 10, 15, 9)


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("tomorrow at ten", 1),
        ("the day after tomorrow", 2),
        ("on Friday", 1),
        ("next Friday", 8),
        ("on Thursday", 7),
        ("in 3 days", 3),
        ("in three days", 3),
        ("today at noon", 0),
        ("set a timer", None),
    ],
)
def test_days(text, expected):
    assert english_time_parser.day_offset(text, now=THURSDAY) == expected


@pytest.mark.parametrize(
    ("text", "hour", "minute"),
    [
        ("Add a dentist appointment tomorrow at ten", 10, 0),
        ("meeting at 3", 15, 0),
        ("at 10:30", 10, 30),
        ("at 7 pm", 19, 0),
        ("at 7:15 p.m.", 19, 15),
        ("12 am", 0, 0),
        ("lunch at noon", 12, 0),
        ("dinner at eight tonight", 20, 0),
        ("Set an alarm for 6:30", 6, 30),
        ("At a dentist appointment tomorrow at 10", 10, 0),
    ],
)
def test_clock_times(text, hour, minute):
    result = english_time_parser.parse(text)
    assert result is not None
    assert result.hour == hour
    assert result.minute == minute


def test_alarms_keep_the_hour_as_said():
    wake = english_time_parser.parse("wake me up at 6", appointment=False)
    tonight = english_time_parser.parse("remind me at 9 tonight", appointment=False)
    assert wake is not None and wake.hour == 6
    assert tonight is not None and tonight.hour == 21


@pytest.mark.parametrize(
    ("text", "appointment_hour", "alarm_hour"),
    [("at 12 at night", 0, 0), ("at 2 at night", 2, 2), ("at 9 at night", 21, 21), ("at 6 in the morning", 6, 6),
     ("at 9 in the evening", 21, 21), ("at 3", 15, 3)],
)  # fmt: skip
def test_a_part_of_the_day_decides_a_bare_hour(text, appointment_hour, alarm_hour):
    appointment = english_time_parser.parse(text)
    alarm = english_time_parser.parse(text, appointment=False)
    assert appointment is not None and appointment.hour == appointment_hour
    assert alarm is not None and alarm.hour == alarm_hour


@pytest.mark.parametrize(
    ("text", "seconds"),
    [
        ("Set a timer for 10 minutes", 600),
        ("in an hour", 3600),
        ("for half an hour", 1800),
        ("1 hour 15 minutes", 4500),
        ("forty five seconds", 45),
        ("in twenty minutes", 1200),
    ],
)
def test_durations(text, seconds):
    result = english_time_parser.parse(text)
    assert result is not None
    assert result.duration_seconds == seconds


def test_nothing_to_read():
    assert english_time_parser.parse("Add milk to my list") is None
    assert english_time_parser.parse("Turn the volume to 30 percent") is None


@pytest.mark.parametrize(
    ("text", "expected"),
    [("on November 15", 31), ("the 15th of November", 31), ("October 1st", 351), ("May I add it", None)],
)
def test_dates(text, expected):
    assert english_time_parser.day_offset(text, now=THURSDAY) == expected


@pytest.mark.parametrize(
    ("text", "seconds"),
    [
        ("remind me in half an hour", 1800),
        ("remind me in 2 hours", 7200),
        ("20 minutes from now", 1200),
        ("remind me in 3 days", None),
        ("remind me at 3 in the afternoon", None),
        ("a 2 hour meeting", None),
    ],
)
def test_time_from_now(text, seconds):
    assert english_time_parser.seconds_from_now(text) == seconds
