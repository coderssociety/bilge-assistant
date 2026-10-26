from datetime import datetime, timedelta

from bilge.core.language import AssistantLanguage
from bilge.core.routines import routine_choice
from bilge.core.routines.routine_schedule import (
    EVERY_DAY,
    WEEKDAYS,
    WEEKEND,
    PartOfDay,
    Routine,
    describe,
    due,
    next_occurrence,
    part_of_day,
)

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
# A Thursday.
THURSDAY = datetime(2026, 10, 15, 20, 59, 50)
GRACE = timedelta(minutes=10)
NIGHTLY = Routine("a", EVERY_DAY, 21, 0, "hava durumunu söyle")
WEEKDAY_MORNINGS = Routine("b", WEEKDAYS, 7, 0, "haberleri oku")


def test_a_routine_is_due_once_when_its_time_passes():
    assert due([NIGHTLY], THURSDAY, THURSDAY + timedelta(seconds=15), GRACE) == [NIGHTLY]
    later = THURSDAY + timedelta(seconds=15)
    assert due([NIGHTLY], later, later + timedelta(seconds=15), GRACE) == []


def test_only_on_its_days():
    saturday_morning = datetime(2026, 10, 17, 6, 59, 55)
    assert due([WEEKDAY_MORNINGS], saturday_morning, saturday_morning + timedelta(seconds=10), GRACE) == []
    friday_morning = datetime(2026, 10, 16, 6, 59, 55)
    assert due([WEEKDAY_MORNINGS], friday_morning, friday_morning + timedelta(seconds=10), GRACE) == [WEEKDAY_MORNINGS]


def test_a_time_missed_long_ago_is_skipped_rather_than_run_late():
    # The computer slept from 20:00 to 23:00.
    assert due([NIGHTLY], datetime(2026, 10, 15, 20, 0), datetime(2026, 10, 15, 23, 0), GRACE) == []
    assert due([NIGHTLY], datetime(2026, 10, 15, 20, 0), datetime(2026, 10, 15, 21, 5), GRACE) == [NIGHTLY]


def test_next_occurrence_skips_the_days_it_does_not_run_on():
    friday_evening = datetime(2026, 10, 16, 20, 0)
    assert next_occurrence(WEEKDAY_MORNINGS, friday_evening) == datetime(2026, 10, 19, 7, 0)
    assert next_occurrence(NIGHTLY, friday_evening) == datetime(2026, 10, 16, 21, 0)


def test_the_schedule_is_said_back():
    assert describe(EVERY_DAY, 21, 0, TR) == "her gün 21:00'de"
    assert describe(WEEKDAYS, 7, 0, TR) == "hafta içi her gün 07:00'de"
    assert describe(WEEKEND, 10, 30, TR) == "hafta sonları 10:30'da"
    assert describe(frozenset({0}), 9, 0, TR) == "her pazartesi 09:00'da"
    assert describe(frozenset({0, 2, 4}), 8, 0, TR) == "pazartesi, çarşamba ve cuma günleri 08:00'de"
    assert describe(EVERY_DAY, 21, 0, EN) == "every day at 21:00"
    assert describe(frozenset({0, 2}), 8, 30, EN) == "on Mondays and Wednesdays at 08:30"


def test_routines_are_chosen_by_part_of_day_or_by_what_they_do():
    evening = Routine("c", EVERY_DAY, 19, 0, "salonun ışığını aç")
    listed = [WEEKDAY_MORNINGS, evening, NIGHTLY]
    assert part_of_day(19) is PartOfDay.EVENING and part_of_day(21) is PartOfDay.NIGHT
    assert routine_choice.chosen(listed, "aksam") == [evening]
    assert routine_choice.chosen(listed, "evening") == [evening]
    assert routine_choice.chosen(listed, "hava durumu") == [NIGHTLY]
    assert routine_choice.chosen(listed, "sabah haber") == [WEEKDAY_MORNINGS]
    assert routine_choice.chosen(listed, "makarna") == []
    assert routine_choice.chosen(listed, "", 2) == [evening]
    assert routine_choice.chosen(listed, None) == listed
