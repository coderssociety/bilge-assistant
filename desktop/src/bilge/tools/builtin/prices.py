"""Gold prices (Truncgil, Altınkaynak) and fuel prices (Opet, Petrol Ofisi) in Turkey. None of these need an
account or a key; the last good answer is kept and told with its age when every source fails."""

import threading
from collections.abc import Callable
from datetime import datetime, timedelta
from typing import Any

from bilge.core import text
from bilge.core.language import AssistantLanguage
from bilge.core.web import fuel_prices, gold_prices, price_text, turkish_provinces
from bilge.core.web.fuel_prices import Fuel
from bilge.core.web.gold_prices import Gold
from bilge.tools import web_fetch
from bilge.tools.base import Tool, ToolError

EN = AssistantLanguage.ENGLISH
TRUNCGIL = "https://finans.truncgil.com/today.json"
ALTINKAYNAK = "https://static.altinkaynak.com/public/Gold"
OPET = "https://api.opet.com.tr/api/fuelprices/prices?ProvinceCode="
PETROL_OFISI = "https://www.petrolofisi.com.tr/akaryakit-fiyatlari/"
# Asked again within this, the kept answer is told without fetching.
GOLD_FRESH = timedelta(minutes=2)
FUEL_FRESH = timedelta(minutes=30)
# Older than this, a kept answer is no longer told.
GOLD_STALE = timedelta(hours=24)
FUEL_STALE = timedelta(days=3)


class KeptPrices:
    """The last good prices per key and when they came."""

    def __init__(self, clock: Callable[[], datetime] = datetime.now) -> None:
        self._clock = clock
        self._lock = threading.Lock()
        self._kept: dict[str, tuple[dict, datetime]] = {}

    def keep(self, key: str, prices: dict) -> None:
        with self._lock:
            self._kept = {**self._kept, key: (prices, self._clock())}

    def within(self, key: str, limit: timedelta) -> tuple[dict, timedelta] | None:
        """The kept prices and their age, if younger than `limit`."""
        with self._lock:
            found = self._kept.get(key)
        if found is None:
            return None
        age = self._clock() - found[1]
        return (found[0], age) if age < limit else None


def _stale_note(age: timedelta, language: AssistantLanguage) -> str:
    if language is EN:
        return f"I couldn't get the current prices; these are from {price_text.age(age, language)} ago. "
    return f"Güncel fiyatları alamadım; bunlar {price_text.age(age, language)} önceki fiyatlar. "


def _failure(error: web_fetch.WebFetchError | None, language: AssistantLanguage, what: tuple[str, str]) -> ToolError:
    english = language is EN
    said = f"Couldn't get {what[1]}." if english else f"{what[0]} alınamadı."
    return ToolError(f"{said} {web_fetch.describe(error, language)}" if error else said)


def _choices(value: Any, allowed: type) -> list:
    values = value if isinstance(value, list) else [value] if value else []
    chosen = []
    for item in values:
        try:
            choice = allowed(item)
        except ValueError:
            continue
        if choice not in chosen:
            chosen.append(choice)
    return chosen


def gold_price(language: AssistantLanguage, kept: KeptPrices | None = None) -> Tool:
    english = language is EN
    kept = kept or KeptPrices()

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        said = gold_prices.kinds(command, english)
        return {"kinds": [k.value for k in said or _choices(arguments.get("kinds"), Gold)]}

    def fetch(asked: list[Gold]) -> tuple[dict[Gold, gold_prices.Quote], timedelta | None]:
        fresh = kept.within("gold", GOLD_FRESH)
        if fresh is not None and all(kind in fresh[0] for kind in asked):
            return fresh[0], None
        quotes: dict[Gold, gold_prices.Quote] = {}
        failure: web_fetch.WebFetchError | None = None
        for url, parse in ((TRUNCGIL, gold_prices.from_truncgil), (ALTINKAYNAK, gold_prices.from_altinkaynak)):
            if all(kind in quotes for kind in asked):
                break
            try:
                # The first source wins where both have a price.
                quotes = {**parse(web_fetch.get_json(url, language)), **quotes}
            except web_fetch.WebFetchError as error:
                failure = failure or error
        if any(kind in quotes for kind in asked):
            kept.keep("gold", quotes)
            return quotes, None
        last = kept.within("gold", GOLD_STALE)
        if last is not None:
            return last
        raise _failure(failure, language, ("Altın fiyatları", "gold prices"))

    def run(arguments: dict[str, Any]) -> str:
        asked = _choices(arguments.get("kinds"), Gold) or list(gold_prices.SUMMARY)
        quotes, age = fetch(asked)
        told = gold_prices.sentence(quotes, asked, language)
        if told is None:
            raise _failure(None, language, ("Bu altın fiyatı", "that gold price"))
        return (_stale_note(age, language) if age is not None else "") + told

    return Tool(
        "goldPrice",
        "Gold prices in Turkey: gram gold, quarter (çeyrek), half, full and Republic (Cumhuriyet) coins, and the ounce."
        if english
        else "Altın fiyatlarını söyler: gram altın, çeyrek, yarım, tam, cumhuriyet ve ata altın, ons.",
        run=run,
        parameters={
            "type": "object",
            "properties": {
                "kinds": {
                    "type": "array",
                    "items": {"type": "string", "enum": [kind.value for kind in Gold]},
                    "description": "Which gold; leave empty for gold prices in general"
                    if english
                    else "Hangi altın; genel olarak soruluyorsa boş bırak",
                },
            },
        },
        refine=refine,
    )


def fuel_price(language: AssistantLanguage, default_city: Callable[[], str], kept: KeptPrices | None = None) -> Tool:
    english = language is EN
    kept = kept or KeptPrices()

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        """A province only if named; the fuels said win over the model's."""
        province = turkish_provinces.find(command)
        said = fuel_prices.kinds(command, english)
        return {
            "city": province.name if province else None,
            "fuels": [f.value for f in said or _choices(arguments.get("fuels"), Fuel)],
            "asian_side": "anadolu" in text.folded(command).split(),
        }

    def fetch(province: turkish_provinces.Province, asian: bool, asked: list[Fuel]) -> tuple[dict, timedelta | None]:
        key = f"{province.plate}{'-asia' if asian else ''}"
        fresh = kept.within(key, FUEL_FRESH)
        if fresh is not None and all(fuel in fresh[0] for fuel in asked):
            return fresh[0], None
        # Opet has no LPG: an earlier Opet answer stays when Petrol Ofisi is asked only for that.
        prices: dict[Fuel, fuel_prices.Price] = dict(fresh[0]) if fresh is not None else {}
        failure: web_fetch.WebFetchError | None = None
        if any(fuel in (Fuel.BENZIN, Fuel.MOTORIN) and fuel not in prices for fuel in asked):
            code = fuel_prices.opet_province(province.plate, asian)
            try:
                prices = {**prices, **fuel_prices.from_opet(web_fetch.get_json(f"{OPET}{code}", language))}
            except web_fetch.WebFetchError as error:
                failure = error
        if any(fuel not in prices for fuel in asked):
            try:
                prices = {**_petrol_ofisi(province, asian, language), **prices}
            except web_fetch.WebFetchError as error:
                failure = failure or error
        if any(fuel in prices for fuel in asked):
            kept.keep(key, prices)
            return prices, None
        last = kept.within(key, FUEL_STALE)
        if last is not None:
            return last
        raise _failure(failure, language, ("Akaryakıt fiyatları", "fuel prices"))

    def run(arguments: dict[str, Any]) -> str:
        city = str(arguments.get("city") or "").strip() or default_city()
        province = turkish_provinces.find(city)
        if province is None:
            raise ToolError(
                f"I only know fuel prices for provinces in Turkey, and '{city}' isn't one."
                if english
                else f"Akaryakıt fiyatlarını yalnızca Türkiye'deki iller için biliyorum; '{city}' bir il değil."
            )
        asked = _choices(arguments.get("fuels"), Fuel) or list(Fuel)
        prices, age = fetch(province, bool(arguments.get("asian_side")), asked)
        told = fuel_prices.sentence(province.name, prices, asked, language)
        if told is None:
            raise _failure(None, language, ("Bu akaryakıt fiyatı", "that fuel price"))
        return (_stale_note(age, language) if age is not None else "") + told

    return Tool(
        "fuelPrice",
        "Fuel prices per liter in a Turkish province: petrol (95 octane), diesel and LPG (Opet, Petrol Ofisi)."
        if english
        else "Bir ildeki akaryakıt litre fiyatlarını söyler: benzin, motorin ve LPG (Opet, Petrol Ofisi).",
        run=run,
        parameters={
            "type": "object",
            "properties": {
                "city": {
                    "type": "string",
                    "description": "Province name only; leave empty if none was said"
                    if english
                    else "İl adı, eksiz: 'İzmir'de' → 'İzmir'; söylenmediyse boş bırak",
                },
                "fuels": {
                    "type": "array",
                    "items": {"type": "string", "enum": [fuel.value for fuel in Fuel]},
                    "description": "Which fuels; leave empty for all"
                    if english
                    else "Hangi yakıt; hepsi için boş bırak",
                },
            },
        },
        refine=refine,
    )


def _petrol_ofisi(
    province: turkish_provinces.Province, asian: bool, language: AssistantLanguage
) -> dict[Fuel, fuel_prices.Price]:
    slug = fuel_prices.petrol_ofisi_slug(province.name)
    response = web_fetch.get(f"{PETROL_OFISI}{slug}-akaryakit-fiyatlari", language)
    if response.status != 200:
        raise web_fetch.WebFetchError(web_fetch.Reason.STATUS, response.status)
    return fuel_prices.from_petrol_ofisi(response.text(), asian)


def asks_for_fuel_prices(language: AssistantLanguage) -> Callable[[str], bool]:
    """ "Benzin ne kadar", "İzmir'de motorin": routed by rule, so no model guesses a price."""
    return lambda command: fuel_prices.claims(
        command, language is EN, names_place=turkish_provinces.find(command) is not None
    )
