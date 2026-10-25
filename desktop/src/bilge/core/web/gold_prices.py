"""Gold prices: which ones a question asks about ("gram altın", "çeyrek altın", "cumhuriyet altını", "ons"), read
from Truncgil's today.json or Altınkaynak's public price list, and the spoken answer."""

from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from bilge.core import text
from bilge.core.language import AssistantLanguage
from bilge.core.tools import currency_request
from bilge.core.web.price_text import amount, turkish_number


class Gold(StrEnum):
    GRAM = "gram"
    CEYREK = "ceyrek"
    YARIM = "yarim"
    TAM = "tam"
    CUMHURIYET = "cumhuriyet"
    ATA = "ata"
    ONS = "ons"


@dataclass(frozen=True)
class Quote:
    buying: float
    selling: float
    # "TRY", or "USD" for the ounce.
    currency: str


# "Altın fiyatları" with no kind named.
SUMMARY = (Gold.GRAM, Gold.CEYREK, Gold.ONS)
_TURKISH_KINDS = (("gram", Gold.GRAM), ("ceyrek", Gold.CEYREK), ("yarim", Gold.YARIM), ("cumhuriyet", Gold.CUMHURIYET),
                  ("ons", Gold.ONS))  # fmt: skip
_TURKISH_EXACT = {"tam": Gold.TAM, "ata": Gold.ATA}
_ENGLISH_KINDS = {
    "gram": Gold.GRAM, "grams": Gold.GRAM, "quarter": Gold.CEYREK, "ceyrek": Gold.CEYREK, "half": Gold.YARIM,
    "full": Gold.TAM, "whole": Gold.TAM, "republic": Gold.CUMHURIYET, "cumhuriyet": Gold.CUMHURIYET, "ata": Gold.ATA,
    "ounce": Gold.ONS, "ounces": Gold.ONS, "oz": Gold.ONS, "ons": Gold.ONS,
}  # fmt: skip
_TRUNCGIL_KEYS = {
    Gold.GRAM: "gram-altin", Gold.CEYREK: "ceyrek-altin", Gold.YARIM: "yarim-altin", Gold.TAM: "tam-altin",
    Gold.CUMHURIYET: "cumhuriyet-altini", Gold.ATA: "ata-altin", Gold.ONS: "ons",
}  # fmt: skip
# Altınkaynak's codes; the ones without a "P" are the counter prices closest to other sources.
_ALTINKAYNAK_CODES = {
    Gold.GRAM: "GA", Gold.CEYREK: "C", Gold.YARIM: "Y", Gold.TAM: "T", Gold.CUMHURIYET: "A_T", Gold.ATA: "A_T",
    Gold.ONS: "XAUUSD",
}  # fmt: skip
_TURKISH_NAMES = {
    Gold.GRAM: "Gram altın", Gold.CEYREK: "Çeyrek altın", Gold.YARIM: "Yarım altın", Gold.TAM: "Tam altın",
    Gold.CUMHURIYET: "Cumhuriyet altını", Gold.ATA: "Ata altın", Gold.ONS: "Ons altın",
}  # fmt: skip
_ENGLISH_NAMES = {
    Gold.GRAM: "A gram of gold", Gold.CEYREK: "A quarter gold coin", Gold.YARIM: "A half gold coin",
    Gold.TAM: "A full gold coin", Gold.CUMHURIYET: "A Republic gold coin", Gold.ATA: "An Ata gold coin",
    Gold.ONS: "An ounce of gold",
}  # fmt: skip


def kinds(command: str, english: bool) -> list[Gold]:
    """The kinds named, in the order said; empty when the question is about gold in general."""
    found: list[Gold] = []
    for word in text.folded(command).split():
        if english:
            kind = _ENGLISH_KINDS.get(word)
        else:
            kind = _TURKISH_EXACT.get(word) or next((k for stem, k in _TURKISH_KINDS if word.startswith(stem)), None)
        if kind is not None and kind not in found:
            found.append(kind)
    return found


def _quote(buying: Any, selling: Any, currency: str) -> Quote | None:
    buy, sell = turkish_number(buying), turkish_number(selling)
    if buy is None and sell is None:
        return None
    return Quote(buy if buy is not None else sell, sell if sell is not None else buy, currency)


def from_truncgil(data: Any) -> dict[Gold, Quote]:
    """finans.truncgil.com/today.json: {"gram-altin": {"Alış": "6.383,95", "Satış": "6.384,76", ...}, ...}."""
    quotes: dict[Gold, Quote] = {}
    for kind, key in _TRUNCGIL_KEYS.items():
        entry = data.get(key) if isinstance(data, dict) else None
        if not isinstance(entry, dict):
            continue
        selling = str(entry.get("Satış") or "")
        found = _quote(entry.get("Alış"), selling, "USD" if kind is Gold.ONS or "$" in selling else "TRY")
        if found is not None:
            quotes[kind] = found
    return quotes


def from_altinkaynak(data: Any) -> dict[Gold, Quote]:
    """static.altinkaynak.com/public/Gold: [{"Kod": "GA", "Alis": "6.398", "Satis": "6.510", ...}, ...]."""
    by_code = {str(e.get("Kod")): e for e in data if isinstance(e, dict)} if isinstance(data, list) else {}
    quotes: dict[Gold, Quote] = {}
    for kind, code in _ALTINKAYNAK_CODES.items():
        entry = by_code.get(code)
        found = _quote(entry.get("Alis"), entry.get("Satis"), "USD" if kind is Gold.ONS else "TRY") if entry else None
        if found is not None:
            quotes[kind] = found
    return quotes


def sentence(quotes: dict[Gold, Quote], asked: list[Gold], language: AssistantLanguage) -> str | None:
    """None when none of the asked prices is known."""
    english = language is AssistantLanguage.ENGLISH
    said = []
    for kind in asked:
        quote = quotes.get(kind)
        if quote is None:
            continue
        unit = ("dollars" if english else "dolar") if quote.currency == "USD" else "lira"
        buying, selling = amount(quote.buying, language), amount(quote.selling, language)
        if english:
            said.append(f"{_ENGLISH_NAMES[kind]}: buying {buying}, selling {selling} {unit}.")
        else:
            said.append(f"{_TURKISH_NAMES[kind]}: alış {buying}, satış {selling} {unit}.")
    return " ".join(said) or None


def claims(command: str, english: bool) -> bool:
    """ "Gram altın kaç lira", and "ons kaç dolar", where the ounce is gold without saying so."""
    if currency_request.asks_for_gold(command, english):
        return True
    words = text.folded(command).split()
    priced = any(w.startswith(("kac", "fiyat", "ne", "price", "much")) for w in words)
    return "ons" in words and priced
