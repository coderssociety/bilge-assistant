import pytest

from bilge.brain.agent import resolve
from bilge.core.language import AssistantLanguage
from bilge.core.tools.currency_request import amount, asks_for_gold, conversion, currencies, number


@pytest.mark.parametrize(
    ("command", "codes"),
    [
        ("100 Euro kaç para", ["EUR", "TRY"]),
        ("dolar kaç lira", ["USD", "TRY"]),
        ("100 liraya kaç dolar alırım", ["TRY", "USD"]),
        ("avro ne kadar", ["EUR"]),
        ("50 sterlin kaç euro", ["GBP", "EUR"]),
        ("€20 kaç TL", ["EUR", "TRY"]),
        ("100 Kanada doları kaç lira", ["CAD", "TRY"]),
        ("how much is £50 in dollars", ["GBP", "USD"]),
        ("yeni kur ne", []),
    ],
)
def test_currencies_in_the_order_said(command, codes):
    assert currencies(command) == codes


@pytest.mark.parametrize(
    ("command", "english", "value"),
    [
        ("100 Euro kaç para", False, 100.0),
        ("1.250 dolar kaç lira", False, 1250.0),
        ("2,5 euro kaç lira", False, 2.5),
        ("€20 kaç TL", False, 20.0),
        ("dolar kaç lira", False, None),
        ("how much is $1,250.50 in euros", True, 1250.5),
        ("convert 2.5 pounds", True, 2.5),
        ("1.000.000 lira kaç dolar", False, 1_000_000.0),
        ("2.500,50 lira kaç euro", False, 2500.5),
    ],
)
def test_the_amount_said_with_the_currency(command, english, value):
    assert amount(command, english) == value


@pytest.mark.parametrize(
    ("command", "sources", "target"),
    [
        ("dolar ve euro kaç lira", ["USD", "EUR"], "TRY"),
        ("dolar ve euro", ["USD", "EUR"], None),
        ("50 dolar kaç sterlin", ["USD"], "GBP"),
        ("100 Euro kaç para", ["EUR"], "TRY"),
        ("100 Kanada doları kaç lira", ["CAD"], "TRY"),
        ("dollar and euro in lira", ["USD", "EUR"], "TRY"),
        ("avro ne kadar", ["EUR"], None),
    ],
)
def test_the_currencies_asked_about_and_the_one_to_give_them_in(command, sources, target):
    assert conversion(command) == (sources, target)


def test_numbers_are_read_with_the_languages_separators():
    assert number("1.000.000", english=False) == 1_000_000.0
    assert number("2.500,50", english=False) == 2500.5
    assert number("1,000,000", english=True) == 1_000_000.0
    assert number("bin", english=False) is None


def test_spoken_numbers_are_digits_by_the_time_they_are_read():
    assert amount(resolve("yüz euro kaç para", AssistantLanguage.TURKISH), english=False) == 100.0


@pytest.mark.parametrize(
    ("command", "english", "gold"),
    [
        ("gram altın kaç lira", False, True),
        ("çeyrek altın ne kadar", False, True),
        ("altın fiyatları", False, True),
        ("masanın altında kaç lira var", False, False),
        ("dolar kaç lira", False, False),
        ("what's the gold price", True, True),
        ("how much is an ounce of gold", True, True),
        ("golden retriever", True, False),
    ],
)
def test_knows_a_question_about_gold(command, english, gold):
    assert asks_for_gold(command, english) is gold
