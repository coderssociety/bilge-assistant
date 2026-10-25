import pytest

from bilge.core.tools import timer_phrase_parser
from bilge.core.tools.timer_phrase_parser import Result


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("20:00'de ilacımı hatırlat", Result(hour=20, minute=0, duration_seconds=None)),
        ("yarın 07:30'da uyandır", Result(hour=7, minute=30, duration_seconds=None)),
        ("45 dakikalık zamanlayıcı kur", Result(hour=None, minute=None, duration_seconds=2700)),
        ("1 saat 15 dakika sonra hatırlat", Result(hour=None, minute=None, duration_seconds=4500)),
        ("30 saniye say", Result(hour=None, minute=None, duration_seconds=30)),
        ("2 buçuk saat sonra", Result(hour=None, minute=None, duration_seconds=9000)),
        ("Yarım saat sonra uyar", Result(hour=None, minute=None, duration_seconds=1800)),
        ("çeyrek saatlik zamanlayıcı", Result(hour=None, minute=None, duration_seconds=900)),
    ],
)
def test_reads_clock_times_and_durations_from_resolved_command_text(text, expected):
    assert timer_phrase_parser.parse(text) == expected


def test_returns_none_when_nothing_precise_is_said():
    assert timer_phrase_parser.parse("çay için zamanlayıcı kur") is None


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        # As turkish_number_parser and turkish_time_of_day leave them.
        ("8'e çeyrek kala alarm kur", Result(hour=7, minute=45, duration_seconds=None, either_half_day=True)),
        ("9'u çeyrek geçe uyandır", Result(hour=9, minute=15, duration_seconds=None, either_half_day=True)),
        ("8'e 10 kala uyandır", Result(hour=7, minute=50, duration_seconds=None, either_half_day=True)),
        ("20:00'e çeyrek kala hatırlat", Result(hour=19, minute=45, duration_seconds=None)),
        ("07:00'yi 20 geçe uyandır", Result(hour=7, minute=20, duration_seconds=None)),
        ("00:00'a çeyrek kala", Result(hour=23, minute=45, duration_seconds=None)),
    ],
)
def test_reads_quarter_to_and_past_the_hour(text, expected):
    assert timer_phrase_parser.parse(text) == expected


@pytest.mark.parametrize(
    ("text", "seconds"),
    [
        ("3 çeyrek saat sonra uyar", 2700),
        ("3 çeyrek sonra", 2700),
        ("bir buçuk saat sonra uyar", 5400),
        ("Bir buçuk dakika say", 90),
        ("yarım saat sonra", 1800),
        ("çeyrek saat sonra", 900),
    ],
)
def test_reads_fractions_of_an_hour(text, seconds):
    assert timer_phrase_parser.parse(text) == Result(hour=None, minute=None, duration_seconds=seconds)


def test_an_article_bir_is_not_a_number():
    assert timer_phrase_parser.parse("bir zamanlayıcı kur") is None
