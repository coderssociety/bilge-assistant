import json
from datetime import datetime, timedelta, timezone

import pytest

from bilge.core.language import AssistantLanguage
from bilge.tools import web_fetch
from bilge.tools.base import ToolError
from bilge.tools.builtin import stocks

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
NOW = datetime(2026, 10, 26, 14, 0, tzinfo=timezone(timedelta(hours=3)))
CHART = {"chart": {"result": [{"meta": {"currency": "TRY", "regularMarketPrice": 338.0, "chartPreviousClose": 338.25,
                                        "regularMarketTime": int(NOW.timestamp())}}]}}  # fmt: skip


def fake_web(monkeypatch, answers, asked):
    """`answers` maps a host to a status, or to an error to raise."""

    def get(url, language=TR, max_bytes=0, user_agent=""):
        asked.append((url, user_agent))
        answer = next(value for host, value in answers.items() if url.startswith(host))
        if isinstance(answer, Exception):
            raise answer
        body = CHART if answer == 200 else {"chart": {"result": None, "error": {"code": "Not Found"}}}
        return web_fetch.Response(url, answer, "application/json", json.dumps(body).encode())

    monkeypatch.setattr(web_fetch, "get", get)


def tool(language=TR):
    return stocks.stocks(language, clock=lambda: NOW)


def test_a_share_is_asked_for_like_a_browser(monkeypatch):
    asked = []
    fake_web(monkeypatch, {stocks.HOSTS[0]: 200}, asked)
    aselsan = tool()
    assert aselsan.run(aselsan.refine({}, "Aselsan bugün")) == "Aselsan (ASELS) 338,00 lira, günlük yüzde 0,07 düşüşte."
    assert asked == [("https://query1.finance.yahoo.com/v8/finance/chart/ASELS.IS?range=1d&interval=1d",
                      web_fetch.BROWSER_USER_AGENT)]  # fmt: skip


def test_the_second_host_answers_when_the_first_fails(monkeypatch):
    asked = []
    fake_web(monkeypatch, {stocks.HOSTS[0]: 429, stocks.HOSTS[1]: 200}, asked)
    assert tool(EN).run({"stock": "XU100"}) == "BIST 100 is at 338.00 points, down 0.07% on the day."
    assert [url.split("/v8")[0] for url, _ in asked] == list(stocks.HOSTS)


def test_an_unknown_code_is_said_without_trying_the_other_host(monkeypatch):
    asked = []
    fake_web(monkeypatch, {stocks.HOSTS[0]: 404, stocks.HOSTS[1]: 404}, asked)
    with pytest.raises(ToolError, match="Borsa İstanbul'da ABCDE diye bir hisse bulamadım."):
        tool().run({"stock": "ABCDE"})
    assert len(asked) == 1


def test_when_both_hosts_fail_it_says_so(monkeypatch):
    error = web_fetch.WebFetchError(web_fetch.Reason.CONNECT)
    fake_web(monkeypatch, {stocks.HOSTS[0]: error, stocks.HOSTS[1]: error}, [])
    with pytest.raises(ToolError, match="Borsa verisi alınamadı. Sunucuya bağlanamadım."):
        tool().run({})


def test_the_share_said_wins_and_borsa_alone_is_the_index():
    shares = tool()
    assert shares.refine({"stock": "GARAN"}, "THY hissesi") == {"stock": "THYAO"}
    assert shares.refine({}, "borsa nasıl") == {"stock": "XU100"}
    assert shares.refine({"stock": "KONTR"}, "Kontrolmatik hissesi") == {"stock": "KONTR"}


def test_prices_are_kept_for_a_minute(monkeypatch):
    asked = []
    fake_web(monkeypatch, {stocks.HOSTS[0]: 200}, asked)
    shares = tool()
    shares.run({"stock": "THYAO"})
    shares.run({"stock": "THYAO"})
    assert len(asked) == 1


@pytest.mark.parametrize(
    ("command", "claimed"),
    [
        ("borsa nasıl", True),
        ("BIST 100 kaç", True),
        ("THY hissesi", True),
        ("Aselsan bugün", False),
        ("hisse senedi nedir", False),
        ("how is the stock market", True),
    ],
)
def test_the_rule_takes_clear_market_questions(command, claimed):
    assert stocks.asks_about_stocks(command) is claimed
