"""Borsa İstanbul prices from Yahoo Finance's public chart service: the BIST 100 and single shares, with the day's
change. Figures only; the tool never says whether to buy or sell."""

import logging
import re
from collections.abc import Callable
from datetime import datetime
from typing import Any

from bilge.core import text
from bilge.core.language import AssistantLanguage
from bilge.core.web import stock_quote
from bilge.tools import web_fetch
from bilge.tools.base import Tool, ToolError
from bilge.tools.feed_cache import TimedCache, get_json

log = logging.getLogger(__name__)
EN = AssistantLanguage.ENGLISH

# The second host answers when the first refuses or fails; both serve the same data.
HOSTS = ("https://query1.finance.yahoo.com", "https://query2.finance.yahoo.com")
CACHE_SECONDS = 60
_MARKET = re.compile(r"\b(borsa\w*|bist\w*|hisse\w*|endeks\w*|stock\w*|shares?|share price)\b")


def _local_now() -> datetime:
    return datetime.now().astimezone()


def asks_about_stocks(command: str) -> bool:
    """ "Borsa nasıl", "THY hissesi", "BIST 100 kaç": by rule, so no model makes up a price."""
    return _MARKET.search(text.folded(command)) is not None and stock_quote.mentioned(command) is not None


def quote(symbol: str, language: AssistantLanguage) -> stock_quote.Quote:
    """From the first host, or the second when the first fails; an unknown code comes back as 404 from both."""
    last: web_fetch.WebFetchError | None = None
    for host in HOSTS:
        url = f"{host}/v8/finance/chart/{symbol}?range=1d&interval=1d"
        try:
            return stock_quote.parse_chart(get_json(url, language, web_fetch.BROWSER_USER_AGENT))
        except web_fetch.WebFetchError as error:
            last = error
            if error.reason is web_fetch.Reason.STATUS and error.status == 404:
                break
        except ValueError as error:
            log.info("Yahoo's chart for %s didn't read: %s", symbol, error)
            last = web_fetch.WebFetchError(web_fetch.Reason.UNEXPECTED)
    raise last or web_fetch.WebFetchError(web_fetch.Reason.UNEXPECTED)


def stocks(
    language: AssistantLanguage, clock: Callable[[], datetime] = _local_now, cache: TimedCache | None = None
) -> Tool:
    english = language is EN
    cache = cache or TimedCache()

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        """A share named in the command wins; "borsa" alone, or nothing recognisable, means the BIST 100."""
        said = stock_quote.mentioned(command)
        if said is not None:
            return {"stock": said.symbol}
        asked = stock_quote.named(str(arguments.get("stock") or ""))
        return {"stock": asked.symbol if asked else stock_quote.INDEX_SYMBOL}

    def run(arguments: dict[str, Any]) -> str:
        stock = stock_quote.named(str(arguments.get("stock") or stock_quote.INDEX_SYMBOL))
        if stock is None:
            raise ToolError(
                "I don't know that share; tell me its Borsa İstanbul code."
                if english
                else "Bu hisseyi tanımıyorum; Borsa İstanbul kodunu söyler misin?"
            )
        try:
            found = cache.get(stock.yahoo, CACHE_SECONDS, lambda: quote(stock.yahoo, language))
        except web_fetch.WebFetchError as error:
            if error.reason is web_fetch.Reason.STATUS and error.status == 404:
                raise ToolError(
                    f"I couldn't find {stock.symbol} on Borsa İstanbul."
                    if english
                    else f"Borsa İstanbul'da {stock.symbol} diye bir hisse bulamadım."
                ) from error
            raise ToolError(
                ("Couldn't get the price. " if english else "Borsa verisi alınamadı. ")
                + web_fetch.describe(error, language)
            ) from error
        return stock_quote.spoken(stock, found, clock(), language)

    return Tool(
        "stocks",
        "Borsa İstanbul figures from Yahoo Finance: the BIST 100 or a share's price and its daily change ('THY', "
        "'Aselsan'). Figures only, never advice."
        if english
        else "Borsa İstanbul verisi (Yahoo Finance): BIST 100 endeksi ya da bir hissenin fiyatı ve günlük değişimi "
        "('THY hissesi', 'Aselsan bugün'). Yalnızca rakamlar; asla yatırım tavsiyesi değil.",
        run=run,
        parameters={
            "type": "object",
            "properties": {
                "stock": {
                    "type": "string",
                    "description": "Share or index as said, or its code (THYAO); empty for the BIST 100"
                    if english
                    else "Söylenen hisse ya da endeks, veya kodu (THYAO); 'borsa' için boş bırak",
                }
            },
        },
        refine=refine,
    )
