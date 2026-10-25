import json
from datetime import datetime, timedelta, timezone

import pytest

from bilge.core.language import AssistantLanguage
from bilge.tools import web_fetch
from bilge.tools.base import ToolError
from bilge.tools.builtin import football

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
NOW = datetime(2026, 10, 25, 19, 30, tzinfo=timezone(timedelta(hours=3)))


def side(where, name, score=None):
    return {"homeAway": where, "team": {"displayName": name}, "score": score}


def match(date, home, away, state, scores=(None, None), clock=""):
    return {"id": f"{home}-{away}", "date": date, "status": {"displayClock": clock, "type": {"state": state}},
            "competitions": [{"competitors": [side("home", home, scores[0]), side("away", away, scores[1])]}]}  # fmt: skip


PAGES = {
    "scoreboard?dates=20261024": {"events": [match("2026-10-24T16:00Z", "Samsunspor", "Amed SFK", "post", ("1", "2"))]},
    "scoreboard?dates=20261025": {"events": [match("2026-10-25T16:00Z", "Goztepe", "Çorum FK", "in", ("1", "0"), "58'")]},
    "scoreboard?dates=20261026": {"events": [match("2026-10-26T18:30Z", "Galatasaray", "Fenerbahce", "pre")]},
    "scoreboard?dates=": {"events": []},
    "/teams/432/schedule?fixture=true": {"events": [match("2026-10-26T18:30Z", "Galatasaray", "Fenerbahce", "pre")]},
    "/teams/432/schedule": {"events": [match("2026-10-17T16:00Z", "Genclerbirligi", "Galatasaray", "post", ("0", "1"))]},
    "/teams": {"sports": [{"leagues": [{"teams": [{"team": {"id": "432", "displayName": "Galatasaray"}},
                                                  {"team": {"id": "789", "displayName": "Goztepe"}}]}]}]},
}  # fmt: skip


def fake_web(monkeypatch, pages=PAGES, asked=None):
    def get(url, language=TR, max_bytes=0, user_agent=""):
        if asked is not None:
            asked.append(url)
        for part, body in pages.items():
            if part in url:
                return web_fetch.Response(url, 200, "application/json", json.dumps(body).encode())
        raise web_fetch.WebFetchError(web_fetch.Reason.CONNECT)

    monkeypatch.setattr(web_fetch, "get", get)


def tool(language=TR):
    return football.football(language, clock=lambda: NOW)


def ask(tool, command):
    return tool.run(tool.refine({}, command))


@pytest.mark.parametrize(
    ("command", "arguments"),
    [
        ("Galatasaray maçı kaç kaç", {"request": "team", "team": "Galatasaray", "next": False}),
        ("Fenerbahçe ne zaman oynuyor", {"request": "team", "team": "Fenerbahçe", "next": True}),
        ("bu hafta Süper Lig maçları", {"request": "week"}),
        ("puan durumu", {"request": "table", "team": ""}),
        ("Trabzonspor kaçıncı sırada", {"request": "table", "team": "Trabzonspor"}),
        ("dün maç sonuçları", {"request": "day", "day_offset": -1}),
        ("bugünkü maçlar", {"request": "day", "day_offset": 0}),
        ("yesterday's results", {"request": "day", "day_offset": -1}),
        ("Süper Lig", {"request": "week"}),
    ],
)
def test_reads_what_is_asked(command, arguments):
    assert football.read(command) == arguments


def test_a_team_named_by_the_model_but_not_said_is_dropped():
    assert tool().refine({"request": "team", "team": "Galatasaray"}, "bu hafta maçlar") == {"request": "week"}


@pytest.mark.parametrize(
    ("command", "claimed"),
    [
        ("Galatasaray maçı kaç kaç", True),
        ("GS kaç kaç", True),
        ("puan durumu", True),
        ("Süper Lig maçları", True),
        ("when does Besiktas play", True),
        ("Galatasaray Lisesi nerede", False),
        ("Trabzon'da hava nasıl", False),
    ],
)
def test_the_rule_takes_football_questions(command, claimed):
    assert football.asks_about_football(command) is claimed


def test_a_live_match_gives_the_score_and_minute(monkeypatch):
    fake_web(monkeypatch)
    assert ask(tool(), "Göztepe maçı kaç kaç") == "Göztepe 1, Çorum FK 0, 58. dakika."


def test_without_a_match_today_the_last_result_and_the_next_match(monkeypatch):
    fake_web(monkeypatch)
    assert ask(tool(), "Galatasaray maçı kaç kaç") == (
        "Son maç: Gençlerbirliği 0, Galatasaray 1, maç bitti (17 Ekim Cumartesi). "
        "Sıradaki: Galatasaray - Fenerbahçe maçı yarın saat 21:30'da."
    )
    assert ask(tool(EN), "when does GS play next") == "Galatasaray v Fenerbahçe, tomorrow at 21:30."


def test_a_day_and_the_week(monkeypatch):
    fake_web(monkeypatch)
    assert ask(tool(), "dün maç sonuçları") == "Dün Süper Lig: Samsunspor 1, Amedspor 2, maç bitti."
    assert ask(tool(), "bu hafta Süper Lig maçları") == (
        "Bu hafta Süper Lig. Dün: Samsunspor 1, Amedspor 2, maç bitti. Bugün: Göztepe 1, Çorum FK 0, 58. dakika. "
        "Yarın: Galatasaray - Fenerbahçe maçı saat 21:30'da."
    )
    assert ask(tool(EN), "today's matches") == "Süper Lig today: Göztepe 1, Çorum FK 0, minute 58."


def test_a_day_without_matches(monkeypatch):
    fake_web(monkeypatch, {"scoreboard": {"events": []}})
    assert tool().run({"request": "day", "day_offset": 1}) == "Yarın Süper Lig maçı yok."


def test_a_club_outside_the_league_this_season(monkeypatch):
    fake_web(monkeypatch)
    assert ask(tool(), "Sivasspor maçı kaç kaç") == "Sivasspor bu sezon Süper Lig'de yok."


def test_answers_are_kept_for_a_while(monkeypatch):
    asked = []
    fake_web(monkeypatch, asked=asked)
    football_tool = tool()
    ask(football_tool, "Göztepe maçı kaç kaç")
    ask(football_tool, "Göztepe maçı kaç kaç")
    assert len(asked) == 1


def test_a_failure_is_said_clearly(monkeypatch):
    fake_web(monkeypatch, {})
    with pytest.raises(ToolError, match="Maç bilgisi alınamadı. Sunucuya bağlanamadım."):
        ask(tool(), "puan durumu")
    fake_web(monkeypatch, {"standings": {"children": []}})
    with pytest.raises(ToolError, match="Couldn't get the football results. The server sent an answer"):
        ask(tool(EN), "standings")
