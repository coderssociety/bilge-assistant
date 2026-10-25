import json
from datetime import datetime, timedelta, timezone

import pytest

from bilge.core.language import AssistantLanguage
from bilge.tools import web_fetch
from bilge.tools.base import ToolError
from bilge.tools.builtin import prayer

from ..fixtures import web_json

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
TURKEY = timezone(timedelta(hours=3))
DIYANET = {
    "https://ezanvakti.emushaf.net/sehirler/2": web_json("ezanvakti_sehirler.json"),
    "https://ezanvakti.emushaf.net/ilceler/506": web_json("ezanvakti_ilceler_ankara.json"),
    "https://ezanvakti.emushaf.net/vakitler/9206": web_json("ezanvakti_vakitler_ankara.json"),
}


def fake_web(monkeypatch, pages, asked, status=200):
    def get(url, language=TR, max_bytes=0):
        asked.append(url)
        for prefix, body in pages.items():
            if url.startswith(prefix):
                return web_fetch.Response(url, status, "application/json", json.dumps(body).encode())
        raise web_fetch.WebFetchError(web_fetch.Reason.CONNECT)

    monkeypatch.setattr(web_fetch, "get", get)


def tool(language=TR, now=datetime(2026, 10, 25, 16, 50, tzinfo=TURKEY), city="Ankara"):
    return prayer.prayer_times_tool(language, lambda: city, clock=lambda: now)


def test_refine_takes_the_vakit_day_and_city_from_the_words():
    ankara = tool()
    assert ankara.refine({"city": "İzmir", "vakit": "ogle"}, "akşam ezanı kaçta") == {
        "city": None, "vakit": "aksam", "occasion": None, "day_offset": 0, "whole_day": False, "remaining": False,
    }  # fmt: skip
    asked = ankara.refine({}, "Konya'da yarın imsak kaçta")
    assert (asked["city"], asked["vakit"], asked["day_offset"]) == ("Konya", "imsak", 1)
    assert ankara.refine({"city": "Kadıköy"}, "Kadıköy'de yatsı kaçta")["city"] == "Kadıköy"
    assert ankara.refine({"vakit": "ikindi"}, "when is it")["vakit"] == "ikindi"


def test_answers_from_diyanets_table_and_keeps_it(monkeypatch):
    asked = []
    fake_web(monkeypatch, DIYANET, asked)
    ankara = tool()
    assert ankara.run(ankara.refine({}, "akşam ezanı kaçta")) == "Ankara'da akşam ezanı 18:03'te; 1 saat 13 dakika var."
    assert ankara.run(ankara.refine({}, "iftara kaç dakika kaldı")) == "Ankara'da iftar 18:03'te; 1 saat 13 dakika var."
    assert len(asked) == 3


def test_falls_back_to_aladhan_when_diyanet_is_busy(monkeypatch):
    asked = []
    fake_web(monkeypatch, {"https://api.aladhan.com": web_json("aladhan_ankara.json")}, asked)
    ankara = tool(now=datetime(2026, 10, 25, 9, 0, tzinfo=TURKEY))
    told = ankara.run(ankara.refine({}, "bugünkü namaz vakitleri"))
    assert told.startswith("Ankara'da bugün namaz vakitleri: imsak 05:39")
    assert asked[0] == "https://ezanvakti.emushaf.net/sehirler/2"
    assert asked[-1] == "https://api.aladhan.com/v1/timingsByCity/25-10-2026?city=Ankara&country=Turkey&method=13"


def test_a_city_that_is_not_a_province_goes_to_aladhan(monkeypatch):
    asked = []
    fake_web(monkeypatch, {"https://api.aladhan.com": web_json("aladhan_ankara.json")}, asked)
    ankara = tool(now=datetime(2026, 10, 25, 9, 0, tzinfo=TURKEY))
    ankara.run({"city": "Kadıköy", "whole_day": True})
    assert all(url.startswith("https://api.aladhan.com") for url in asked)
    assert "city=Kad%C4%B1k%C3%B6y" in asked[0]


def test_says_clearly_when_no_source_answers(monkeypatch):
    fake_web(monkeypatch, {}, [])
    with pytest.raises(ToolError, match="Namaz vakitleri alınamadı. Sunucuya bağlanamadım."):
        tool().run({"vakit": "aksam"})
    fake_web(monkeypatch, DIYANET, [], status=429)
    with pytest.raises(ToolError, match="Couldn't get the prayer times. The site is busy"):
        tool(EN).run({})


def test_english_next_prayer(monkeypatch):
    fake_web(monkeypatch, DIYANET, [])
    english = tool(EN, now=datetime(2026, 10, 25, 21, 0, tzinfo=TURKEY))
    assert english.run(english.refine({}, "how long until the next prayer")) == (
        "The next prayer time in Ankara is fajr (imsak), tomorrow at 05:40, in 8 hours 40 minutes."
    )
