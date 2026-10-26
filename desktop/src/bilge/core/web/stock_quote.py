"""Borsa İstanbul: shares and indices by the names people say ("THY", "Aselsan", "borsa"), Yahoo Finance's chart
answer read into a price and the day's change, and the spoken figures. Figures only: never advice."""

import math
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.core.web import spoken_names
from bilge.core.web.spoken_dates import day_phrase

EN = AssistantLanguage.ENGLISH
INDEX_SYMBOL = "XU100"


@dataclass(frozen=True)
class Stock:
    symbol: str
    name: str
    aliases: tuple[str, ...] = ()

    @property
    def is_index(self) -> bool:
        return self.symbol.startswith("XU")

    @property
    def yahoo(self) -> str:
        return f"{self.symbol}.IS"


STOCKS = (
    Stock("XU100", "BIST 100", ("BIST 100", "BIST yüz", "borsa", "Borsa İstanbul", "endeks", "BIST", "stock market")),
    Stock("XU030", "BIST 30", ("BIST 30", "BIST otuz")),
    Stock("THYAO", "Türk Hava Yolları", ("THY", "Türk Hava Yolları", "Turkish Airlines")),
    Stock("ASELS", "Aselsan", ("Aselsan",)),
    Stock("GARAN", "Garanti BBVA", ("Garanti", "Garanti Bankası")),
    Stock("AKBNK", "Akbank", ("Akbank",)),
    Stock("YKBNK", "Yapı Kredi", ("Yapı Kredi",)),
    Stock("ISCTR", "İş Bankası", ("İş Bankası", "Türkiye İş Bankası")),
    Stock("VAKBN", "Vakıfbank", ("Vakıfbank", "Vakıf Bank")),
    Stock("HALKB", "Halkbank", ("Halkbank", "Halk Bankası")),
    Stock("KCHOL", "Koç Holding", ("Koç Holding", "Koç")),
    Stock("SAHOL", "Sabancı Holding", ("Sabancı Holding", "Sabancı")),
    Stock("TUPRS", "Tüpraş", ("Tüpraş",)),
    Stock("EREGL", "Ereğli Demir Çelik", ("Ereğli", "Erdemir", "Ereğli Demir Çelik")),
    Stock("KRDMD", "Kardemir", ("Kardemir",)),
    Stock("BIMAS", "BİM", ("BİM", "BİM Mağazaları")),
    Stock("MGROS", "Migros", ("Migros",)),
    Stock("SOKM", "Şok Marketler", ("Şok Market", "Şok Marketler")),
    Stock("SISE", "Şişecam", ("Şişecam",)),
    Stock("FROTO", "Ford Otosan", ("Ford Otosan", "Ford")),
    Stock("TOASO", "Tofaş", ("Tofaş",)),
    Stock("PGSUS", "Pegasus", ("Pegasus",)),
    Stock("TAVHL", "TAV Havalimanları", ("TAV",)),
    Stock("TCELL", "Turkcell", ("Turkcell",)),
    Stock("TTKOM", "Türk Telekom", ("Türk Telekom",)),
    Stock("ARCLK", "Arçelik", ("Arçelik",)),
    Stock("VESTL", "Vestel", ("Vestel",)),
    Stock("PETKM", "Petkim", ("Petkim",)),
    Stock("SASA", "Sasa Polyester", ("Sasa",)),
    Stock("HEKTS", "Hektaş", ("Hektaş",)),
    Stock("ASTOR", "Astor Enerji", ("Astor",)),
    Stock("ENKAI", "Enka İnşaat", ("Enka",)),
    Stock("EKGYO", "Emlak Konut", ("Emlak Konut",)),
    Stock("ULKER", "Ülker", ("Ülker",)),
    Stock("AEFES", "Anadolu Efes", ("Anadolu Efes", "Efes")),
    Stock("CCOLA", "Coca-Cola İçecek", ("Coca Cola", "Coca-Cola İçecek")),
    Stock("TKFEN", "Tekfen", ("Tekfen",)),
    Stock("ALARK", "Alarko", ("Alarko",)),
    Stock("GUBRF", "Gübretaş", ("Gübretaş",)),
    Stock("DOHOL", "Doğan Holding", ("Doğan Holding",)),
    Stock("OYAKC", "Oyak Çimento", ("Oyak Çimento",)),
    Stock("MAVI", "Mavi Giyim", ("Mavi Giyim",)),
)


def mentioned(command: str) -> Stock | None:
    """ "THY hissesi", "Aselsan bugün", "borsa nasıl", "THYAO kaç"."""
    names = [(spelling, stock) for stock in STOCKS for spelling in (stock.symbol, stock.name, *stock.aliases)]
    return spoken_names.find(command, names)


def named(name: str) -> Stock | None:
    """The model's argument: a listed name, or any Borsa İstanbul code ("KONTR") even if the table lacks it."""
    found = mentioned(name)
    if found is not None:
        return found
    code = name.strip().upper().removesuffix(".IS")
    return Stock(code, code) if re.fullmatch(r"[A-Z][A-Z0-9]{2,5}", code) else None


@dataclass(frozen=True)
class Quote:
    price: float
    previous_close: float
    time: datetime
    currency: str

    @property
    def change_percent(self) -> float:
        return (self.price - self.previous_close) / self.previous_close * 100


def parse_chart(data: Any) -> Quote:
    """Yahoo's v8 chart for a one-day range: `chartPreviousClose` is then the close of the trading day before."""
    try:
        meta = data["chart"]["result"][0]["meta"]
        price = float(meta["regularMarketPrice"])
        previous = float(meta.get("chartPreviousClose") or meta["previousClose"])
        time = datetime.fromtimestamp(int(meta["regularMarketTime"]), UTC)
    except (KeyError, IndexError, TypeError, ValueError) as error:
        raise ValueError("Yahoo sent no price") from error
    if not (math.isfinite(price) and math.isfinite(previous) and previous > 0):
        raise ValueError("Yahoo sent an impossible price")
    return Quote(price, previous, time, str(meta.get("currency") or "TRY"))


def number(value: float, language: AssistantLanguage) -> str:
    """Two decimals, Turkish separators in Turkish: 11.116,99 / 11,116.99."""
    formatted = f"{value:,.2f}"
    if language is not EN:
        formatted = formatted.replace(",", "\x00").replace(".", ",").replace("\x00", ".")
    return formatted


def spoken(stock: Stock, quote: Quote, now: datetime, language: AssistantLanguage) -> str:
    """ "THY (THYAO) 258,00 lira, yüzde 0,39 düşüşte." With the day named when the last trade wasn't today."""
    english = language is EN
    change = quote.change_percent
    size = number(abs(change), language)
    price = number(quote.price, language)
    traded = quote.time.astimezone(now.tzinfo)
    label = stock.name if stock.is_index or stock.name == stock.symbol else f"{stock.name} ({stock.symbol})"
    if english:
        unit = " points" if stock.is_index else (" lira" if quote.currency == "TRY" else f" {quote.currency}")
        move = "unchanged" if round(change, 2) == 0 else f"{'up' if change > 0 else 'down'} {size}%"
        when = (
            "on the day" if traded.date() == now.date() else f"at the last close ({day_phrase(traded, now, language)})"
        )
        return f"{label} is at {price}{unit}, {move} {when}."
    unit = " puan" if stock.is_index else (" lira" if quote.currency == "TRY" else f" {quote.currency}")
    move = "değişmedi" if round(change, 2) == 0 else f"yüzde {size} {'yükselişte' if change > 0 else 'düşüşte'}"
    when = "" if traded.date() == now.date() else f" (son işlem: {day_phrase(traded, now, language)})"
    return f"{label} {price}{unit}, günlük {move}{when}."
