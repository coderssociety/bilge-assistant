from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from bilge.core.tools import relative_day_parser

ISTANBUL = ZoneInfo("Europe/Istanbul")
TUESDAY = datetime(2026, 10, 13, 9, tzinfo=ISTANBUL)


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("bugün saat 15:00'te toplantı", 0),
        ("yarın 10:00'da diş hekimi", 1),
        ("öbür gün sabah", 2),
        ("ertesi gün", 1),
        ("cuma günü toplantı ekle", 3),
        ("Pazartesi annemi ara", 6),
        ("salı günü", 7),
        ("haftaya çarşamba", 8),
        ("3 gün sonra", 3),
        ("cumaya toplantı koy", 3),
        ("perşembeden sonra", 2),
        ("pazar günü", 5),
        ("gelecek hafta cuma", 10),
        ("yarından sonra", 2),
        ("haftaya", 7),
        ("haftaya bugün", 7),
        ("2 hafta sonra", 14),
        ("15 Kasım'da toplantı", 33),
        ("10 Ekim'de", 362),
    ],
)
def test_resolves_relative_day_words_to_a_day_offset(text, expected):
    assert relative_day_parser.day_offset(text, now=TUESDAY, tz=ISTANBUL) == expected


def test_returns_none_when_no_day_is_mentioned():
    assert relative_day_parser.day_offset("15:00'te toplantı ekle", now=TUESDAY, tz=ISTANBUL) is None


@pytest.mark.parametrize(
    ("text", "expected"),
    [("yarın pazara gitmeyi hatırlat", 1), ("pazarda domates al", None), ("salıncak kur", None)],
)
def test_words_that_only_begin_like_a_weekday_are_not_one(text, expected):
    assert relative_day_parser.day_offset(text, now=TUESDAY, tz=ISTANBUL) == expected


def test_an_impossible_date_is_no_date():
    assert relative_day_parser.day_offset("31 Şubat", now=TUESDAY, tz=ISTANBUL) is None
