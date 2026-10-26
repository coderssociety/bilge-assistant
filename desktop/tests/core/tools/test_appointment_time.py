import pytest

from bilge.brain.agent import resolve
from bilge.core.language import AssistantLanguage
from bilge.core.tools import appointment_time


def heard(said: str) -> str:
    return resolve(said, AssistantLanguage.TURKISH)


@pytest.mark.parametrize(
    ("said", "expected"),
    [
        ("yarın saat ikide toplantı ekle", (14, 0)),
        ("saat altıda", (18, 0)),
        ("saat yedide", (7, 0)),
        ("sabah saat ikide uçak", (2, 0)),
        ("sabah ikide", (2, 0)),
        ("akşam sekizde yemek", (20, 0)),
        ("akşam saat sekizde", (20, 0)),
        ("akşamları 8'de haberleri oku", (20, 0)),
        ("geceleri 11'de", (23, 0)),
        ("her gece saat 12'de haberleri oku", (0, 0)),
        ("gece saat 2'de", (2, 0)),
        ("gece saat 23'te", (23, 0)),
        ("öğlen saat 12'de", (12, 0)),
        ("sabahları 2'de", (2, 0)),
        ("dokuz buçukta toplantı", (9, 30)),
        ("saat üç buçukta", (15, 30)),
        ("saat on beşte", (15, 0)),
        ("3'te diş hekimi", (15, 0)),
        ("10:30'da", (10, 30)),
        ("2:30'da", (14, 30)),
        ("15 Kasım'da toplantı", None),
        ("bir buçuk saat sonra", None),
        ("toplantı ekle", None),
    ],
)
def test_reads_the_clock_time_with_afternoon_for_small_hours(said, expected):
    assert appointment_time.clock(heard(said)) == expected


@pytest.mark.parametrize(
    ("said", "seconds"),
    [
        ("yarım saat sonra hatırlat", 1800),
        ("iki saat sonra hatırlat", 7200),
        ("on dakika sonra çayı hatırlat", 600),
        ("bir saat on beş dakika sonra", 4500),
        ("saat ikide hatırlat", None),
        ("üç gün sonra hatırlat", None),
    ],
)
def test_reads_how_far_ahead(said, seconds):
    assert appointment_time.seconds_from_now(heard(said)) == seconds
