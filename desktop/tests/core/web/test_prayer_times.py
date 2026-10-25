from datetime import date, datetime, time, timedelta, timezone

import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.web import prayer_answer, prayer_times
from bilge.core.web.prayer_times import Occasion, Question, Vakit

from ...fixtures import web_json

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
TURKEY = timezone(timedelta(hours=3))


def ankara():
    return prayer_times.from_ezanvakti(web_json("ezanvakti_vakitler_ankara.json"))


def at(hour, minute, day=25):
    return datetime(2026, 10, day, hour, minute, tzinfo=TURKEY)


def test_reads_diyanets_month_table():
    days = ankara()
    assert sorted(days) == [date(2026, 10, 24), date(2026, 10, 25), date(2026, 10, 26)]
    assert days[date(2026, 10, 25)].times == {
        Vakit.IMSAK: time(5, 39), Vakit.GUNES: time(7, 2), Vakit.OGLE: time(12, 38), Vakit.IKINDI: time(15, 34),
        Vakit.AKSAM: time(18, 3), Vakit.YATSI: time(19, 22),
    }  # fmt: skip


def test_skips_broken_days_and_answers_that_are_not_a_table():
    good = web_json("ezanvakti_vakitler_ankara.json")[0]
    broken = {**good, "MiladiTarihKisa": "31.02.2026"}
    missing = {key: value for key, value in good.items() if key != "Aksam"}
    assert list(prayer_times.from_ezanvakti([broken, missing, "x", good])) == [date(2026, 10, 24)]
    assert prayer_times.from_ezanvakti({"error": "busy"}) == {}


def test_reads_aladhans_diyanet_method():
    day = prayer_times.from_aladhan(web_json("aladhan_ankara.json"))
    assert day.day == date(2026, 10, 25)
    assert day.times[Vakit.IMSAK] == time(5, 39)
    assert day.times[Vakit.AKSAM] == time(18, 2)
    assert prayer_times.from_aladhan({"code": 503, "data": "Geocoding is temporarily unavailable."}) is None


def test_finds_the_province_and_its_centre():
    assert prayer_times.province_id(web_json("ezanvakti_sehirler.json"), "İstanbul") == "539"
    assert prayer_times.province_id(web_json("ezanvakti_sehirler.json"), "Kahramanmaraş") == "541"
    assert prayer_times.province_id(web_json("ezanvakti_sehirler.json"), "Hatay") is None
    assert prayer_times.centre_id(web_json("ezanvakti_ilceler_ankara.json"), "Ankara") == "9206"
    assert prayer_times.centre_id([], "Ankara") is None


@pytest.mark.parametrize(
    ("command", "english", "claimed"),
    [
        ("akşam ezanı kaçta", False, True),
        ("ezana ne kadar var", False, True),
        ("iftara kaç dakika kaldı", False, True),
        ("yarın imsak kaçta", False, True),
        ("bugünkü namaz vakitleri", False, True),
        ("Ankara'da öğle ezanı", False, True),
        ("yatsı kaçta", False, True),
        ("ezan nedir", False, False),
        ("namaz nasıl kılınır", False, False),
        ("iftar menüsü öner", False, False),
        ("akşam hava nasıl", False, False),
        ("when is maghrib", True, True),
        ("how long until iftar", True, True),
        ("prayer times in Konya", True, True),
        ("what is iftar", True, False),
    ],
)
def test_claims_only_questions_about_a_prayer_time(command, english, claimed):
    assert prayer_times.claims(command, english) is claimed


@pytest.mark.parametrize(
    ("command", "english", "expected"),
    [
        ("akşam ezanı kaçta", False, Question(Vakit.AKSAM)),
        ("ezana ne kadar var", False, Question(remaining=True)),
        ("iftara kaç dakika kaldı", False, Question(Vakit.AKSAM, Occasion.IFTAR, remaining=True)),
        ("sahur ne zaman bitiyor", False, Question(Vakit.IMSAK, Occasion.SAHUR)),
        ("sabah ezanı", False, Question(Vakit.IMSAK)),
        ("öğleden sonra ezan", False, Question()),
        ("bugünkü namaz vakitleri", False, Question(whole_day=True)),
        ("when is fajr", True, Question(Vakit.IMSAK)),
        ("prayer times", True, Question(whole_day=True)),
        ("how long until iftar", True, Question(Vakit.AKSAM, Occasion.IFTAR, remaining=True)),
    ],
)
def test_reads_what_the_question_asks(command, english, expected):
    assert prayer_times.question(command, english) == expected


def test_the_next_vakit_runs_into_tomorrows_imsak():
    days = ankara()
    assert prayer_times.upcoming(days, at(12, 0)) == (Vakit.OGLE, at(12, 38))
    assert prayer_times.upcoming(days, at(21, 0)) == (Vakit.IMSAK, at(5, 40, day=26))
    assert prayer_times.upcoming(days, at(21, 0, day=26)) is None


def test_time_left_is_rounded_up_to_the_minute():
    assert prayer_answer.remaining(at(18, 3), at(16, 50), english=False) == "1 saat 13 dakika"
    assert prayer_answer.remaining(at(18, 3), datetime(2026, 10, 25, 18, 2, 30, tzinfo=TURKEY), False) == "1 dakika"
    assert prayer_answer.remaining(at(18, 3), at(16, 3), english=True) == "2 hours"
    assert prayer_answer.remaining(at(18, 3), at(17, 2), english=True) == "1 hour 1 minute"


def answer(asked, now, language=TR, day_name="bugün"):
    return prayer_answer.answer(ankara(), now, "Ankara", asked, day_name, language)


def test_answers_the_asked_vakit_with_the_time_left():
    assert answer(Question(Vakit.AKSAM), at(16, 50)) == "Ankara'da akşam ezanı 18:03'te; 1 saat 13 dakika var."
    assert answer(Question(Vakit.AKSAM, Occasion.IFTAR), at(17, 50)) == "Ankara'da iftar 18:03'te; 13 dakika var."
    assert answer(Question(Vakit.AKSAM), at(16, 50), EN) == "In Ankara, maghrib is at 18:03, in 1 hour 13 minutes."


def test_a_vakit_already_past_today_gives_tomorrows_too():
    assert answer(Question(Vakit.OGLE), at(13, 0)) == "Ankara'da bugünkü öğle ezanı 12:38'deydi; yarın 12:38'de."
    assert answer(Question(Vakit.IMSAK), at(13, 0)) == "Ankara'da bugünkü imsak 05:39'daydı; yarın 05:40'ta."
    assert answer(Question(Vakit.OGLE), at(13, 0), EN) == (
        "In Ankara, today's dhuhr was at 12:38; tomorrow it is at 12:38."
    )


def test_answers_the_next_vakit_when_none_is_named():
    assert (
        answer(Question(remaining=True), at(12, 0)) == "Ankara'da sıradaki vakit öğle ezanı: 12:38'de; 38 dakika var."
    )
    assert answer(Question(), at(21, 0)) == "Ankara'da sıradaki vakit imsak: yarın 05:40'ta; 8 saat 40 dakika var."
    assert answer(Question(), at(21, 0), EN) == (
        "The next prayer time in Ankara is fajr (imsak), tomorrow at 05:40, in 8 hours 40 minutes."
    )


def test_answers_another_day_and_the_whole_day():
    assert answer(Question(Vakit.IMSAK, day_offset=1), at(21, 0), day_name="yarın") == "Ankara'da yarın imsak 05:40'ta."
    assert answer(Question(whole_day=True), at(9, 0)) == (
        "Ankara'da bugün namaz vakitleri: imsak 05:39, güneş 07:02, öğle 12:38, ikindi 15:34, akşam 18:03, yatsı 19:22."
    )
    assert answer(Question(whole_day=True, day_offset=1), at(9, 0), EN, "tomorrow") == (
        "Prayer times in Ankara tomorrow: fajr 05:40, sunrise 07:03, dhuhr 12:38, asr 15:33, maghrib 18:02, isha 19:20."
    )


def test_no_answer_without_the_days_needed():
    assert answer(Question(Vakit.AKSAM, day_offset=3), at(9, 0)) is None
    assert answer(Question(whole_day=True), at(9, 0, day=27)) is None
