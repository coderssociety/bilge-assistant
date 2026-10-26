from datetime import UTC, datetime, timedelta, timezone

import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.web import earthquake_report, provinces
from bilge.core.web.earthquake_feed import Earthquake

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
TURKEY = timezone(timedelta(hours=3))
NOW = datetime(2026, 10, 25, 19, 0, tzinfo=TURKEY)


def quake(minutes_ago, magnitude, place, lat, lon, depth=7.0):
    return Earthquake(
        f"x:{place}:{minutes_ago}", NOW - timedelta(minutes=minutes_ago), lat, lon, depth, magnitude, place
    )


QUAKES = [
    quake(3, 4.6, "Sındırgı, Balıkesir", 39.23, 28.08, 10.4),
    quake(50, 2.4, "Bornova, İzmir", 38.47, 27.22),
    quake(120, 1.5, "Menderes, İzmir", 37.92, 27.11),
    quake(19 * 60 + 10, 3.1, "Malatya merkez", 38.35, 38.31),
    quake(30 * 60, 5.0, "Old one", 39.0, 28.0),
]


@pytest.mark.parametrize(
    ("command", "province", "today", "big", "latest"),
    [
        ("son depremler", None, False, False, False),
        ("deprem oldu mu", None, False, False, False),
        ("İzmir'de deprem var mı", "İzmir", False, False, False),
        ("bugün büyük deprem oldu mu", None, True, True, False),
        ("en son deprem nerede", None, False, False, True),
        ("en son depremler", None, False, False, False),
        ("son depremin büyüklüğü kaç", None, False, False, True),
        ("any big earthquakes today", None, True, True, False),
        ("where was the latest earthquake", None, False, False, True),
    ],
)
def test_reads_what_is_asked(command, province, today, big, latest):
    query = earthquake_report.read(command)
    found = (query.province.name if query.province else None, query.today, query.big, query.latest)
    assert found == (province, today, big, latest)


def test_a_place_from_the_model_counts_only_when_said():
    assert earthquake_report.read("deprem oldu mu", "Ankara").province is None
    assert earthquake_report.read("Sındırgı'da deprem oldu mu", "Sındırgı").place == "Sındırgı"


def test_recent_ones_are_listed_newest_first_with_small_ones_and_old_ones_left_out():
    chosen = earthquake_report.select(QUAKES, earthquake_report.Query(), NOW)
    assert [q.place for q in chosen] == ["Sındırgı, Balıkesir", "Bornova, İzmir", "Malatya merkez"]


def test_near_a_province_today_and_big():
    izmir = earthquake_report.Query(province=provinces.named("İzmir"))
    assert [q.place for q in earthquake_report.select(QUAKES, izmir, NOW)] == ["Bornova, İzmir"]
    today_big = earthquake_report.Query(today=True, big=True)
    assert [q.place for q in earthquake_report.select(QUAKES, today_big, NOW)] == ["Sındırgı, Balıkesir"]
    # 19:10 ago is yesterday evening by the user's clock.
    today = earthquake_report.Query(today=True)
    assert "Malatya merkez" not in [q.place for q in earthquake_report.select(QUAKES, today, NOW)]
    district = earthquake_report.Query(place="sindirgi")
    assert [q.place for q in earthquake_report.select(QUAKES, district, NOW)] == ["Sındırgı, Balıkesir"]


def test_the_turkish_answer():
    query = earthquake_report.Query()
    chosen = earthquake_report.select(QUAKES, query, NOW)
    answer = earthquake_report.answer(chosen[:1], query, NOW, TR, provinces.named("İstanbul"))
    assert answer == (
        "Son 24 saatte 2 ve üzeri büyüklükte 1 deprem kaydedildi: Sındırgı, Balıkesir: büyüklük 4,6, 3 dakika önce, "
        "derinlik 10 km, İstanbul'dan 212 km uzakta. Kaynak: AFAD."
    )


def test_the_english_answer_for_the_latest_one():
    query = earthquake_report.Query(latest=True)
    chosen = earthquake_report.select(QUAKES, query, NOW)
    answer = earthquake_report.answer(chosen, query, NOW, EN, None, "Kandilli Observatory")
    assert answer == (
        "The latest earthquake: Sındırgı, Balıkesir: magnitude 4.6, 3 minutes ago, 10 km deep. "
        "Source: Kandilli Observatory."
    )


def test_more_than_five_are_counted_and_the_newest_told():
    many = [quake(i, 3.0, f"Yer {i}", 38.0, 30.0) for i in range(1, 9)]
    answer = earthquake_report.answer(many, earthquake_report.Query(), NOW, TR)
    assert answer.startswith("Son 24 saatte 2 ve üzeri büyüklükte 8 deprem kaydedildi, en yenileri: Yer 1:")
    assert "Yer 5" in answer and "Yer 6" not in answer


def test_nothing_found_says_so():
    near = earthquake_report.Query(province=provinces.named("Van"), today=True, big=True)
    assert earthquake_report.answer([], near, NOW, TR) == (
        "Bugün Van yakınında 4 ve üzeri büyüklükte deprem kaydedilmedi. Kaynak: AFAD."
    )
    assert earthquake_report.answer([], near, NOW, EN) == (
        "No earthquakes of magnitude 4 or more near Van today. Source: AFAD."
    )


@pytest.mark.parametrize(
    ("elapsed", "turkish", "english"),
    [
        (timedelta(seconds=20), "az önce", "just now"),
        (timedelta(minutes=1), "1 dakika önce", "1 minute ago"),
        (timedelta(minutes=59), "59 dakika önce", "59 minutes ago"),
        (timedelta(hours=5, minutes=40), "5 saat önce", "5 hours ago"),
        (timedelta(days=2), "2 gün önce", "2 days ago"),
    ],
)
def test_time_ago(elapsed, turkish, english):
    assert earthquake_report.time_ago(elapsed, TR) == turkish
    assert earthquake_report.time_ago(elapsed, EN) == english


def test_times_compare_across_zones():
    utc = Earthquake("a", datetime(2026, 10, 25, 15, 57, tzinfo=UTC), 39.2, 28.1, 5, 4.0, "X")
    assert earthquake_report.time_ago(NOW - utc.time, TR) == "3 dakika önce"
