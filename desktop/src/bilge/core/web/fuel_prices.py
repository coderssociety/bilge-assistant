"""Fuel prices: which fuel a question asks about ("benzin ne kadar", "İzmir'de motorin", "LPG kaç lira"), read from
Opet's price API or Petrol Ofisi's price page for a province, and the spoken answer."""

import html
import re
from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from bilge.core import text
from bilge.core.language import AssistantLanguage
from bilge.core.web.price_text import amount


class Fuel(StrEnum):
    BENZIN = "benzin"
    MOTORIN = "motorin"
    LPG = "lpg"


@dataclass(frozen=True)
class Price:
    liter: float
    source: str


OPET = "Opet"
PETROL_OFISI = "Petrol Ofisi"
_TURKISH_FUELS = (("benzin", Fuel.BENZIN), ("kursunsuz", Fuel.BENZIN), ("motorin", Fuel.MOTORIN),
                  ("dizel", Fuel.MOTORIN), ("mazot", Fuel.MOTORIN), ("lpg", Fuel.LPG), ("otogaz", Fuel.LPG))  # fmt: skip
_ENGLISH_FUELS = {"petrol": Fuel.BENZIN, "gasoline": Fuel.BENZIN, "gas": Fuel.BENZIN, "unleaded": Fuel.BENZIN,
                  "diesel": Fuel.MOTORIN, "lpg": Fuel.LPG, "autogas": Fuel.LPG}  # fmt: skip
_TURKISH_PRICE_WORDS = frozenset({"kac", "lira", "tl", "para"})
_TURKISH_PRICE_STEMS = ("fiyat", "zam", "indirim")
# "Benzinci", "benzinlik": the station, not the fuel.
_STATIONS = ("benzinci", "benzinlik")
_ENGLISH_PRICE = ("price", "prices", "cost", "costs", "much")
_TURKISH_GENERAL = ("akaryakit", "yakit")
_ENGLISH_GENERAL = ("fuel",)
# Opet's codes: Kurşunsuz Benzin 95, and Motorin EcoForce before UltraForce (both cost the same).
_OPET_CODES = {Fuel.BENZIN: ("A100",), Fuel.MOTORIN: ("A128", "A121")}
# Opet lists İstanbul's European side as 934 and the Asian side under the plate code 34.
OPET_ISTANBUL_EUROPE = 934
ISTANBUL = 34
# Petrol Ofisi's column titles: "V/Max Kurşunsuz 95", "V/Max Diesel", "PO/gaz Otogaz".
_PETROL_OFISI_COLUMNS = (("kursunsuz", Fuel.BENZIN), ("diesel", Fuel.MOTORIN), ("otogaz", Fuel.LPG))
_PETROL_OFISI_SLUGS = {"afyonkarahisar": "afyon"}
_HEADER = re.compile(r"<thead>(.*?)</thead>", re.S)
_HEADING = re.compile(r"<th[^>]*>(.*?)</th>", re.S)
_ROW = re.compile(r'<tr class="price-row[^"]*"[^>]*data-disctrict-name="([^"]*)"[^>]*>(.*?)</tr>', re.S)
_PRICE = re.compile(r'<span class="with-tax">\s*([\d.,]+)\s*</span>')


def kinds(command: str, english: bool) -> list[Fuel]:
    """The fuels named, in the order said; empty for fuel prices in general."""
    found: list[Fuel] = []
    for word in text.folded(command).split():
        if english:
            kind = _ENGLISH_FUELS.get(word)
        else:
            stems = () if word.startswith(_STATIONS) else _TURKISH_FUELS
            kind = next((k for stem, k in stems if word.startswith(stem)), None)
        if kind is not None and kind not in found:
            found.append(kind)
    return found


def claims(command: str, english: bool, names_place: bool) -> bool:
    """A question about the price of a fuel: "benzin ne kadar", or a fuel with a place ("İzmir'de motorin")."""
    folded = text.folded(command)
    words = folded.split()
    general = any(w.startswith(_ENGLISH_GENERAL if english else _TURKISH_GENERAL) for w in words)
    if not kinds(command, english) and not general:
        return False
    if english:
        priced = any(w in _ENGLISH_PRICE for w in words)
    else:
        priced = "ne kadar" in folded or any(
            w in _TURKISH_PRICE_WORDS or w.startswith(_TURKISH_PRICE_STEMS) for w in words
        )
    return priced or names_place or len(words) <= 2


def opet_province(plate: int, asian_side: bool) -> int:
    if plate != ISTANBUL:
        return plate
    return ISTANBUL if asian_side else OPET_ISTANBUL_EUROPE


def from_opet(data: Any) -> dict[Fuel, Price]:
    """api.opet.com.tr/api/fuelprices/prices: one entry per district; the centre ("MERKEZ") speaks for the province."""
    districts = [d for d in data if isinstance(d, dict)] if isinstance(data, list) else []
    centre = next((d for d in districts if "MERKEZ" in str(d.get("districtName") or "")), None)
    chosen = centre or (districts[0] if districts else None)
    listed = chosen.get("prices") if chosen else None
    by_code = {str(p.get("productCode")): p.get("amount") for p in listed if isinstance(p, dict)} if listed else {}
    prices: dict[Fuel, Price] = {}
    for fuel, codes in _OPET_CODES.items():
        value = next((by_code[c] for c in codes if _positive(by_code.get(c))), None)
        if value is not None:
            prices[fuel] = Price(float(value), OPET)
    return prices


def petrol_ofisi_slug(province: str) -> str:
    folded = text.folded(province).replace(" ", "-")
    return _PETROL_OFISI_SLUGS.get(folded, folded)


def from_petrol_ofisi(page: str, asian_side: bool = False) -> dict[Fuel, Price]:
    """The province page: a table whose first row is the province centre (İstanbul has a row for each side)."""
    header = _HEADER.search(page)
    if header is None:
        return {}
    titles = [text.folded(html.unescape(re.sub(r"<[^>]+>", " ", h))) for h in _HEADING.findall(header.group(1))]
    rows = _ROW.findall(page)
    if not rows:
        return {}
    row = next((r for r in rows if asian_side and "ANADOLU" in r[0].upper()), rows[0])
    # The first column holds the place name and has no price.
    values = dict(zip(titles[1:], _PRICE.findall(row[1]), strict=False))
    prices: dict[Fuel, Price] = {}
    for title, value in values.items():
        fuel = next((f for stem, f in _PETROL_OFISI_COLUMNS if stem in title), None)
        number = _dotted(value)
        if fuel is not None and number is not None:
            prices[fuel] = Price(number, PETROL_OFISI)
    return prices


_TURKISH_NAMES = {Fuel.BENZIN: "benzin", Fuel.MOTORIN: "motorin", Fuel.LPG: "LPG"}
_TURKISH_GENITIVES = {Fuel.BENZIN: "benzinin", Fuel.MOTORIN: "motorinin", Fuel.LPG: "LPG'nin"}
_ENGLISH_NAMES = {Fuel.BENZIN: "petrol", Fuel.MOTORIN: "diesel", Fuel.LPG: "LPG"}


def sentence(city: str, prices: dict[Fuel, Price], asked: list[Fuel], language: AssistantLanguage) -> str | None:
    """None when none of the asked prices is known."""
    known = [fuel for fuel in asked if fuel in prices]
    if not known:
        return None
    english = language is AssistantLanguage.ENGLISH
    sources = (" and " if english else " ve ").join(dict.fromkeys(prices[f].source for f in known))
    if len(known) == 1:
        fuel = known[0]
        liter = amount(prices[fuel].liter, language)
        if english:
            return f"In {city}, {_ENGLISH_NAMES[fuel]} is {liter} lira a liter ({sources})."
        return f"{text.locative(city)} {_TURKISH_GENITIVES[fuel]} litresi {liter} lira ({sources})."
    names = _ENGLISH_NAMES if english else _TURKISH_NAMES
    listed = ", ".join(f"{names[f]} {amount(prices[f].liter, language)}" for f in known)
    if english:
        return f"Prices per liter in {city}: {listed} lira ({sources})."
    return f"{text.locative(city)} litre fiyatları: {listed} lira ({sources})."


def _positive(value: Any) -> bool:
    return isinstance(value, int | float) and not isinstance(value, bool) and value > 0


def _dotted(value: str) -> float | None:
    """Petrol Ofisi writes "77.50"."""
    try:
        number = float(value.replace(",", ""))
    except ValueError:
        return None
    return number if number > 0 else None
