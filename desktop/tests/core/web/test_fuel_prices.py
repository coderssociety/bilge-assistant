import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.web import fuel_prices
from bilge.core.web.fuel_prices import Fuel, Price

from ...fixtures import web_bytes, web_json

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH


@pytest.mark.parametrize(
    ("command", "english", "kinds"),
    [
        ("benzin ne kadar", False, [Fuel.BENZIN]),
        ("İzmir'de motorin", False, [Fuel.MOTORIN]),
        ("LPG kaç lira", False, [Fuel.LPG]),
        ("mazotun ve otogazın litresi", False, [Fuel.MOTORIN, Fuel.LPG]),
        ("akaryakıt fiyatları", False, []),
        ("benzinci kaçta açılıyor", False, []),
        ("diesel price in Ankara", True, [Fuel.MOTORIN]),
        ("how much is petrol", True, [Fuel.BENZIN]),
    ],
)
def test_reads_which_fuel_is_asked_about(command, english, kinds):
    assert fuel_prices.kinds(command, english) == kinds


@pytest.mark.parametrize(
    ("command", "english", "place", "claimed"),
    [
        ("benzin ne kadar", False, False, True),
        ("İzmir'de motorin", False, True, True),
        ("LPG kaç lira", False, False, True),
        ("akaryakıt fiyatları", False, False, True),
        ("motorin", False, False, True),
        ("benzin bitti galiba arabada", False, False, False),
        ("benzinci kaçta açılıyor", False, False, False),
        ("diesel price", True, False, True),
        ("I ran out of petrol on the way home", True, False, False),
    ],
)
def test_claims_fuel_price_questions(command, english, place, claimed):
    assert fuel_prices.claims(command, english, place) is claimed


def test_istanbul_has_a_code_for_each_side_at_opet():
    assert fuel_prices.opet_province(34, asian_side=False) == 934
    assert fuel_prices.opet_province(34, asian_side=True) == 34
    assert fuel_prices.opet_province(35, asian_side=True) == 35


def test_reads_opets_centre_district():
    prices = fuel_prices.from_opet(web_json("opet_izmir.json"))
    assert prices == {Fuel.BENZIN: Price(77.51, "Opet"), Fuel.MOTORIN: Price(98.13, "Opet")}
    first = fuel_prices.from_opet(web_json("opet_izmir.json")[:1])
    assert first[Fuel.BENZIN].liter == 77.5
    assert fuel_prices.from_opet([{"districtName": "MERKEZ", "prices": [{"productCode": "A100", "amount": 0}]}]) == {}
    assert fuel_prices.from_opet({"message": "error"}) == {}


def test_reads_petrol_ofisis_page():
    page = web_bytes("petrol_ofisi_istanbul.html").decode()
    assert fuel_prices.from_petrol_ofisi(page) == {
        Fuel.BENZIN: Price(76.30, "Petrol Ofisi"), Fuel.MOTORIN: Price(96.80, "Petrol Ofisi"),
        Fuel.LPG: Price(41.20, "Petrol Ofisi"),
    }  # fmt: skip
    assert fuel_prices.from_petrol_ofisi(page, asian_side=True)[Fuel.LPG] == Price(40.60, "Petrol Ofisi")
    assert fuel_prices.from_petrol_ofisi("<html>Bakımdayız</html>") == {}


def test_petrol_ofisi_page_names():
    assert fuel_prices.petrol_ofisi_slug("İzmir") == "izmir"
    assert fuel_prices.petrol_ofisi_slug("Afyonkarahisar") == "afyon"
    assert fuel_prices.petrol_ofisi_slug("Şanlıurfa") == "sanliurfa"


def test_tells_the_asked_prices_and_their_source():
    prices = {
        Fuel.BENZIN: Price(77.51, "Opet"),
        Fuel.MOTORIN: Price(98.13, "Opet"),
        Fuel.LPG: Price(41.2, "Petrol Ofisi"),
    }
    assert fuel_prices.sentence("İzmir", prices, [Fuel.MOTORIN], TR) == "İzmir'de motorinin litresi 98,13 lira (Opet)."
    assert fuel_prices.sentence("İzmir", prices, list(Fuel), TR) == (
        "İzmir'de litre fiyatları: benzin 77,51, motorin 98,13, LPG 41,20 lira (Opet ve Petrol Ofisi)."
    )
    assert (
        fuel_prices.sentence("Izmir", prices, [Fuel.LPG], EN) == "In Izmir, LPG is 41.20 lira a liter (Petrol Ofisi)."
    )
    assert fuel_prices.sentence("İzmir", {}, [Fuel.LPG], TR) is None
