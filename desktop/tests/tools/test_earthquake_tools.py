import json
from datetime import datetime, timedelta, timezone

import pytest

from bilge.core.language import AssistantLanguage
from bilge.tools import web_fetch
from bilge.tools.base import ToolError
from bilge.tools.builtin import earthquakes

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
NOW = datetime(2026, 10, 25, 19, 0, tzinfo=timezone(timedelta(hours=3)))
AFAD_ROW = {"eventID": "1", "latitude": "38.47", "longitude": "27.22", "depth": "7", "magnitude": "3.4",
            "country": "Türkiye", "province": "İzmir", "district": "Bornova", "date": "2026-10-25T15:50:00"}  # fmt: skip
KANDILLI = (
    "2026.10.25 18:40:56  39.2415   28.0832       11.3      -.-  2.6  -.-   KOZLU-SINDIRGI (BALIKESIR)    İlksel\n"
).encode("windows-1254")


def fake_web(monkeypatch, afad=None, kandilli=None, asked=None):
    def get(url, language=TR, max_bytes=0, user_agent=""):
        if asked is not None:
            asked.append(url)
        body = afad if url.startswith(earthquakes.AFAD_URL) else kandilli
        if body is None:
            raise web_fetch.WebFetchError(web_fetch.Reason.CONNECT)
        return web_fetch.Response(url, 200, "", body)

    monkeypatch.setattr(web_fetch, "get", get)


def tool(language=TR):
    return earthquakes.earthquakes(language, lambda: "İstanbul", clock=lambda: NOW)


def test_afad_answers_with_the_window_and_magnitude_asked(monkeypatch):
    asked = []
    fake_web(monkeypatch, afad=json.dumps([AFAD_ROW]).encode(), asked=asked)
    quakes = tool()
    answer = quakes.run(quakes.refine({}, "İzmir'de deprem var mı"))
    assert answer.startswith("Son 24 saatte İzmir yakınında 2 ve üzeri büyüklükte 1 deprem kaydedildi: Bornova, İzmir")
    assert answer.endswith("Kaynak: AFAD.")
    assert asked == [
        earthquakes.AFAD_URL + "?start=2026-10-24T16%3A00%3A00&end=2026-10-25T16%3A01%3A00&minmag=2&format=json"
    ]


def test_kandilli_answers_when_afad_fails(monkeypatch):
    fake_web(monkeypatch, afad=None, kandilli=KANDILLI)
    quakes = tool(EN)
    answer = quakes.run(quakes.refine({}, "where was the latest earthquake"))
    assert answer.startswith("The latest earthquake: Sindirgi, Balıkesir: magnitude 2.6, 19 minutes ago")
    assert answer.endswith("Source: Kandilli Observatory.")


def test_kandilli_answers_when_afad_sends_something_else(monkeypatch):
    fake_web(monkeypatch, afad=b"<html>bakim</html>", kandilli=KANDILLI)
    assert "Kandilli" in tool().run({})


def test_when_both_fail_it_says_so(monkeypatch):
    fake_web(monkeypatch, afad=None, kandilli=b"<html>changed</html>")
    with pytest.raises(ToolError, match="Deprem bilgisi alınamadı. Sunucudan anlayamadığım bir yanıt geldi."):
        tool().run({})


def test_the_list_is_kept_for_a_minute(monkeypatch):
    asked = []
    fake_web(monkeypatch, afad=b"[]", asked=asked)
    quakes = tool()
    assert quakes.run({}) == "Son 24 saatte 2 ve üzeri büyüklükte deprem kaydedilmedi. Kaynak: AFAD."
    quakes.run({"big": True})
    assert len(asked) == 1


@pytest.mark.parametrize(
    ("command", "claimed"),
    [
        ("son depremler", True),
        ("deprem oldu mu", True),
        ("İzmir'de deprem var mı", True),
        ("bugün büyük deprem oldu mu", True),
        ("en son deprem nerede", True),
        ("was there an earthquake today", True),
        ("deprem çantasına ne koymalıyım", False),
        ("hava nasıl", False),
    ],
)
def test_the_rule_takes_questions_about_earthquakes_that_happened(command, claimed):
    assert earthquakes.asks_about_earthquakes(command) is claimed
