from datetime import UTC, datetime, timedelta, timezone

import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.web import stock_quote

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
NOW = datetime(2026, 10, 26, 14, 0, tzinfo=timezone(timedelta(hours=3)))


def chart(price, previous, at, currency="TRY"):
    meta = {"currency": currency, "regularMarketPrice": price, "chartPreviousClose": previous,
            "regularMarketTime": int(at.timestamp())}  # fmt: skip
    return {"chart": {"result": [{"meta": meta}], "error": None}}


@pytest.mark.parametrize(
    ("command", "symbol"),
    [
        ("borsa nasıl", "XU100"),
        ("BIST 100 kaç", "XU100"),
        ("BIST 30 ne durumda", "XU030"),
        ("THY hissesi", "THYAO"),
        ("THY'nin hissesi ne kadar", "THYAO"),
        ("Aselsan bugün", "ASELS"),
        ("THYAO kaç lira", "THYAO"),
        ("Türk Hava Yolları hisse fiyatı", "THYAO"),
        ("İş Bankası hissesi", "ISCTR"),
        ("Ereğli kaç", "EREGL"),
        ("how is the stock market", "XU100"),
        ("hava nasıl", None),
    ],
)
def test_names_people_say_become_codes(command, symbol):
    found = stock_quote.mentioned(command)
    assert (found.symbol if found else None) == symbol


def test_any_code_the_model_gives_is_tried():
    assert stock_quote.named("kontr").yahoo == "KONTR.IS"
    assert stock_quote.named("THYAO.IS").symbol == "THYAO"
    assert stock_quote.named("bir şey") is None


def test_the_chart_gives_the_price_and_change():
    quote = stock_quote.parse_chart(chart(258.0, 259.0, NOW))
    assert quote.price == 258.0
    assert round(quote.change_percent, 2) == -0.39


@pytest.mark.parametrize(
    "data",
    [
        {"chart": {"result": None, "error": {"code": "Not Found"}}},
        chart("x", 1, NOW),
        chart(10, 0, NOW),
        {},
    ],
)
def test_a_chart_without_a_usable_price_is_an_error(data):
    with pytest.raises(ValueError):
        stock_quote.parse_chart(data)


def test_spoken_figures():
    thy = stock_quote.mentioned("THY")
    index = stock_quote.mentioned("borsa")
    today = stock_quote.parse_chart(chart(258.0, 259.0, NOW))
    assert (
        stock_quote.spoken(thy, today, NOW, TR) == "Türk Hava Yolları (THYAO) 258,00 lira, günlük yüzde 0,39 düşüşte."
    )
    assert stock_quote.spoken(thy, today, NOW, EN) == (
        "Türk Hava Yolları (THYAO) is at 258.00 lira, down 0.39% on the day."
    )
    friday = stock_quote.parse_chart(chart(11116.99, 11000.0, datetime(2026, 10, 23, 15, 10, tzinfo=UTC)))
    assert stock_quote.spoken(index, friday, NOW, TR) == (
        "BIST 100 11.116,99 puan, günlük yüzde 1,06 yükselişte (son işlem: 23 Ekim Cuma)."
    )
    assert stock_quote.spoken(index, friday, NOW, EN) == (
        "BIST 100 is at 11,116.99 points, up 1.06% at the last close (Friday 23 October)."
    )
    flat = stock_quote.parse_chart(chart(10.0, 10.0, NOW))
    assert stock_quote.spoken(stock_quote.named("KONTR"), flat, NOW, TR) == "KONTR 10,00 lira, günlük değişmedi."
