import json
from datetime import datetime, timedelta

import pytest

from bilge.core.language import AssistantLanguage
from bilge.tools import web_fetch
from bilge.tools.base import ToolError
from bilge.tools.builtin import prices

from ..fixtures import web_bytes, web_json

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
GOLD = {prices.TRUNCGIL: web_json("truncgil_today.json"), prices.ALTINKAYNAK: web_json("altinkaynak_gold.json")}
PETROL_OFISI_ISTANBUL = f"{prices.PETROL_OFISI}istanbul-akaryakit-fiyatlari"


def fake_web(monkeypatch, pages, asked):
    def get(url, language=TR, max_bytes=0):
        asked.append(url)
        body = pages.get(url)
        if body is None:
            raise web_fetch.WebFetchError(web_fetch.Reason.CONNECT)
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        return web_fetch.Response(url, 200, "text/html; charset=utf-8", data)

    monkeypatch.setattr(web_fetch, "get", get)


class Clock:
    def __init__(self):
        self.now = datetime(2026, 10, 25, 20, 0)

    def __call__(self):
        return self.now


def test_gold_kinds_come_from_the_words():
    tool = prices.gold_price(TR)
    assert tool.refine({"kinds": ["ons"]}, "çeyrek altın ne kadar") == {"kinds": ["ceyrek"]}
    assert tool.refine({"kinds": ["ons", "platin"]}, "altın fiyatları") == {"kinds": ["ons"]}
    assert tool.refine({}, "altın fiyatları") == {"kinds": []}


def test_gold_reads_truncgil_and_fills_in_from_altinkaynak(monkeypatch):
    asked = []
    fake_web(monkeypatch, GOLD, asked)
    tool = prices.gold_price(TR, prices.KeptPrices(Clock()))
    assert tool.run({"kinds": ["gram"]}) == "Gram altın: alış 6.383,95, satış 6.384,76 lira."
    assert asked == [prices.TRUNCGIL]
    assert tool.run({"kinds": ["yarim"]}) == "Yarım altın: alış 20.540,00, satış 21.445,00 lira."
    assert asked[1:] == [prices.TRUNCGIL, prices.ALTINKAYNAK]
    assert tool.run({}).startswith("Gram altın: alış 6.383,95")


def test_gold_uses_altinkaynak_when_truncgil_is_down(monkeypatch):
    fake_web(monkeypatch, {prices.ALTINKAYNAK: GOLD[prices.ALTINKAYNAK]}, [])
    assert prices.gold_price(EN).run({"kinds": ["gram"]}) == "A gram of gold: buying 6,398.00, selling 6,510.00 lira."


def test_gold_asked_again_soon_is_not_fetched_again(monkeypatch):
    asked = []
    fake_web(monkeypatch, GOLD, asked)
    tool = prices.gold_price(TR, prices.KeptPrices(Clock()))
    tool.run({"kinds": ["gram"]})
    tool.run({"kinds": ["gram"]})
    assert len(asked) == 1


def test_gold_tells_a_kept_price_with_its_age_when_every_source_fails(monkeypatch):
    clock = Clock()
    kept = prices.KeptPrices(clock)
    fake_web(monkeypatch, GOLD, [])
    tool = prices.gold_price(TR, kept)
    tool.run({"kinds": ["gram"]})
    fake_web(monkeypatch, {}, [])
    clock.now += timedelta(minutes=25)
    assert tool.run({"kinds": ["gram"]}) == (
        "Güncel fiyatları alamadım; bunlar 25 dakika önceki fiyatlar. Gram altın: alış 6.383,95, satış 6.384,76 lira."
    )
    clock.now += prices.GOLD_STALE
    with pytest.raises(ToolError, match="Altın fiyatları alınamadı. Sunucuya bağlanamadım."):
        tool.run({"kinds": ["gram"]})


def test_fuel_refine_keeps_only_a_named_province():
    tool = prices.fuel_price(TR, lambda: "İstanbul")
    assert tool.refine({"city": "Ankara", "fuels": ["lpg"]}, "benzin ne kadar") == {
        "city": None, "fuels": ["benzin"], "asian_side": False,
    }  # fmt: skip
    assert tool.refine({}, "İzmir'de motorin")["city"] == "İzmir"
    assert tool.refine({}, "Anadolu yakasında benzin")["asian_side"] is True


def test_fuel_reads_opet_and_lpg_from_petrol_ofisi(monkeypatch):
    asked = []
    pages = {
        f"{prices.OPET}934": web_json("opet_izmir.json"),
        PETROL_OFISI_ISTANBUL: web_bytes("petrol_ofisi_istanbul.html"),
    }
    fake_web(monkeypatch, pages, asked)
    tool = prices.fuel_price(TR, lambda: "İstanbul", prices.KeptPrices(Clock()))
    assert tool.run({"fuels": ["benzin"]}) == "İstanbul'da benzinin litresi 77,51 lira (Opet)."
    assert asked == [f"{prices.OPET}934"]
    assert (
        tool.run({})
        == "İstanbul'da litre fiyatları: benzin 77,51, motorin 98,13, LPG 41,20 lira (Opet ve Petrol Ofisi)."
    )
    assert asked[1:] == [PETROL_OFISI_ISTANBUL]


def test_fuel_falls_back_to_petrol_ofisi_and_reads_the_asian_side(monkeypatch):
    asked = []
    fake_web(monkeypatch, {PETROL_OFISI_ISTANBUL: web_bytes("petrol_ofisi_istanbul.html")}, asked)
    tool = prices.fuel_price(EN, lambda: "Istanbul")
    assert tool.run({"fuels": ["motorin"], "asian_side": True}) == (
        "In İstanbul, diesel is 96.60 lira a liter (Petrol Ofisi)."
    )
    assert asked == [f"{prices.OPET}34", PETROL_OFISI_ISTANBUL]


def test_fuel_needs_a_province_and_says_when_prices_cant_be_had(monkeypatch):
    with pytest.raises(ToolError, match="'Berlin' bir il değil"):
        prices.fuel_price(TR, lambda: "Berlin").run({})
    fake_web(monkeypatch, {}, [])
    with pytest.raises(ToolError, match="Akaryakıt fiyatları alınamadı."):
        prices.fuel_price(TR, lambda: "İzmir").run({"fuels": ["lpg"]})


def test_rules_claim_gold_and_fuel_questions():
    assert prices.asks_for_fuel_prices(TR)("İzmir'de motorin")
    assert not prices.asks_for_fuel_prices(TR)("benzin bitti galiba arabada")
