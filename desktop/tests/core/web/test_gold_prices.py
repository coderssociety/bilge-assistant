from datetime import timedelta

import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.web import gold_prices, price_text
from bilge.core.web.gold_prices import Gold, Quote

from ...fixtures import web_json

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH


@pytest.mark.parametrize(
    ("value", "number"),
    [("6.383,95", 6383.95), ("$3.995,89", 3995.89), ("6.423", 6423.0), ("80,15", 80.15), (12.5, 12.5), ("", None),
     ("yok", None), (True, None)],
)  # fmt: skip
def test_reads_turkish_written_prices(value, number):
    assert price_text.turkish_number(value) == number


def test_speaks_prices_with_the_languages_separators_and_ages():
    assert price_text.amount(6384.756, TR) == "6.384,76"
    assert price_text.amount(6384.756, EN) == "6,384.76"
    assert price_text.age(timedelta(seconds=20), TR) == "1 dakika"
    assert price_text.age(timedelta(hours=3, minutes=5), EN) == "3 hours"
    assert price_text.age(timedelta(days=3), TR) == "3 gün"


@pytest.mark.parametrize(
    ("command", "english", "kinds"),
    [
        ("gram altın ne kadar", False, [Gold.GRAM]),
        ("çeyrek altın kaç lira", False, [Gold.CEYREK]),
        ("cumhuriyet altını", False, [Gold.CUMHURIYET]),
        ("ons kaç dolar", False, [Gold.ONS]),
        ("tam altın ve yarım altın", False, [Gold.TAM, Gold.YARIM]),
        ("ata altın", False, [Gold.ATA]),
        ("altın fiyatları", False, []),
        ("Ataşehir'de altın", False, []),
        ("price of an ounce of gold", True, [Gold.ONS]),
        ("quarter gold coin", True, [Gold.CEYREK]),
    ],
)
def test_reads_which_gold_is_asked_about(command, english, kinds):
    assert gold_prices.kinds(command, english) == kinds


@pytest.mark.parametrize(
    ("command", "english", "claimed"),
    [
        ("gram altın", False, True),
        ("çeyrek altın ne kadar", False, True),
        ("ons kaç dolar", False, True),
        ("masanın altında ne var", False, False),
        ("dolar kaç lira", False, False),
        ("gold price", True, True),
        ("golden retriever", True, False),
    ],
)
def test_claims_gold_price_questions(command, english, claimed):
    assert gold_prices.claims(command, english) is claimed


def test_reads_truncgil():
    quotes = gold_prices.from_truncgil(web_json("truncgil_today.json"))
    assert quotes[Gold.GRAM] == Quote(6383.95, 6384.76, "TRY")
    assert quotes[Gold.ONS] == Quote(3995.89, 3996.40, "USD")
    assert Gold.YARIM not in quotes
    assert gold_prices.from_truncgil({"gram-altin": {"Alış": "", "Satış": "yok"}}) == {}
    assert gold_prices.from_truncgil(["not", "a", "dict"]) == {}


def test_reads_altinkaynak():
    quotes = gold_prices.from_altinkaynak(web_json("altinkaynak_gold.json"))
    assert quotes[Gold.GRAM] == Quote(6398.0, 6510.0, "TRY")
    assert quotes[Gold.YARIM] == Quote(20540.0, 21445.0, "TRY")
    assert quotes[Gold.CUMHURIYET] == quotes[Gold.ATA] == Quote(42241.0, 43304.0, "TRY")
    assert quotes[Gold.ONS].currency == "USD"
    assert gold_prices.from_altinkaynak({"error": True}) == {}


def test_tells_the_asked_prices():
    quotes = gold_prices.from_truncgil(web_json("truncgil_today.json"))
    assert gold_prices.sentence(quotes, [Gold.GRAM, Gold.ONS], TR) == (
        "Gram altın: alış 6.383,95, satış 6.384,76 lira. Ons altın: alış 3.995,89, satış 3.996,40 dolar."
    )
    assert gold_prices.sentence(quotes, [Gold.CEYREK], EN) == (
        "A quarter gold coin: buying 10,322.22, selling 10,560.44 lira."
    )
    assert gold_prices.sentence(quotes, [Gold.YARIM], TR) is None
