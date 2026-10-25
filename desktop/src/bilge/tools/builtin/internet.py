"""Data from the internet: weather (Open-Meteo), exchange rates (European Central Bank via Frankfurter), news
headlines (Anadolu Ajansı / BBC) and reading a web page. None of these need an account or a key."""

import json
import logging
import math
import threading
from collections.abc import Callable
from datetime import datetime, timedelta
from typing import Any
from urllib.parse import urlencode

from bilge.brain.instructions import weekday_name
from bilge.core import text
from bilge.core.language import AssistantLanguage
from bilge.core.tools import currency_request, english_time_parser, relative_day_parser
from bilge.core.web import html_text, news_request, news_source, rss_headlines, weather_report, weather_request
from bilge.core.web import news_article as article_reference
from bilge.tools import web_fetch
from bilge.tools.base import Tool, ToolError
from bilge.tools.reading import TextReading, continued

log = logging.getLogger(__name__)
EN, TR = AssistantLanguage.ENGLISH, AssistantLanguage.TURKISH
HEADLINE_COUNT = 5
# Enough of the feed to go on with after the first few.
FEED_COUNT = 30
# Enough for a long article; the model only sees the start of a longer page.
PAGE_CHARACTERS = 12_000
FORECAST_DAYS = 7


def _json(url: str, language: AssistantLanguage) -> Any:
    response = web_fetch.get(url, language)
    if response.status != 200:
        raise web_fetch.WebFetchError(web_fetch.Reason.STATUS, response.status)
    try:
        return json.loads(response.body)
    except ValueError as error:
        raise web_fetch.WebFetchError(web_fetch.Reason.UNEXPECTED) from error


# How long "peki yarın?" still means the city just asked about.
FOLLOW_UP_WINDOW = timedelta(minutes=5)


class WeatherFollowUp:
    """The city of the last weather answer, so a follow-up that names no city ("peki yarın?") stays there."""

    def __init__(self, clock: Callable[[], datetime] = datetime.now) -> None:
        self._clock = clock
        self._last: tuple[str, datetime] | None = None
        self._lock = threading.Lock()

    def remember(self, city: str) -> None:
        with self._lock:
            self._last = (city, self._clock())

    def recent_city(self) -> str | None:
        with self._lock:
            if self._last is None or self._clock() - self._last[1] >= FOLLOW_UP_WINDOW:
                return None
            return self._last[0]


def weather(
    language: AssistantLanguage, default_city: Callable[[], str], follow_up: WeatherFollowUp | None = None
) -> Tool:
    english = language is EN
    follow_up = follow_up or WeatherFollowUp()

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        # A local model once filled in "Ankara" for "Bugün hava nasıl"; a city counts only if it was said, or was
        # the one just asked about.
        city = str(arguments.get("city") or "").strip()
        if city:
            stem = text.folded(city)[: max(3, len(city) - 1)]
            city = city if any(word.startswith(stem) for word in text.folded(command).split()) else ""
        refined: dict[str, Any] = {**arguments, "city": city or follow_up.recent_city()}
        parsed = (english_time_parser if english else relative_day_parser).day_offset(command, datetime.now())
        if parsed is not None and 0 <= parsed < FORECAST_DAYS:
            refined["day_offset"] = parsed
        part = weather_request.part_of_day(command, english)
        rain = weather_request.asks_about_rain(command, english)
        if (part or rain) and _whole_number(refined.get("day_offset")) is None:
            refined["day_offset"] = 0
        if part:
            refined["part"] = part.value
        if rain:
            refined["rain"] = True
        return refined

    def run(arguments: dict[str, Any]) -> str:
        asked = str(arguments.get("city") or "").strip()
        city = asked or default_city()
        day = _whole_number(arguments.get("day_offset"))
        try:
            part = weather_request.PartOfDay(arguments.get("part"))
        except ValueError:
            part = None
        try:
            places = _json(
                "https://geocoding-api.open-meteo.com/v1/search?"
                + urlencode({"name": city, "count": 1, "language": language.code}),
                language,
            )
            place = (places.get("results") or [None])[0]
            if not place:
                raise ToolError(
                    f"Couldn't find a place called '{city}'." if english else f"'{city}' diye bir yer bulamadım."
                )
            query = {
                "latitude": place["latitude"],
                "longitude": place["longitude"],
                "current": "temperature_2m,weather_code",
                "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
                "timezone": "auto",
                "forecast_days": FORECAST_DAYS,
            }
            if part is not None:
                query["hourly"] = "temperature_2m,precipitation_probability"
            forecast = _json("https://api.open-meteo.com/v1/forecast?" + urlencode(query), language)
        except web_fetch.WebFetchError as error:
            raise ToolError(
                ("Couldn't get the weather. " if english else "Hava durumu alınamadı. ")
                + web_fetch.describe(error, language)
            ) from error
        if asked:
            follow_up.remember(asked)
        daily = forecast["daily"]
        if not isinstance(day, int) or not 0 <= day < len(daily["time"]):
            current = forecast["current"]
            return weather_report.current(place["name"], current["temperature_2m"], current["weather_code"], language)
        if part is not None and forecast.get("hourly"):
            told = _hours(place["name"], forecast["hourly"], day, part, language)
            if told is not None:
                return told
        return weather_report.daily(
            place["name"],
            _day_name(day, language),
            daily["temperature_2m_min"][day],
            daily["temperature_2m_max"][day],
            daily["weather_code"][day],
            daily["precipitation_probability_max"][day],
            language,
            asked_about_rain=bool(arguments.get("rain")),
        )

    return Tool(
        "weather",
        "Weather for a city: now, today, tomorrow, the coming days, a part of the day, or whether it will rain."
        if english
        else "Bir şehrin hava durumunu söyler: şu an, bugün, yarın, önümüzdeki günler, günün bir bölümü ya da yağmur "
        "yağıp yağmayacağı.",
        run=run,
        parameters={
            "type": "object",
            "properties": {
                "city": {
                    "type": "string",
                    "description": "City name only; leave empty if none was said"
                    if english
                    else "Şehir adı, eksiz: 'Ankara'da' → 'Ankara'; söylenmediyse boş bırak",
                },
                "day_offset": {
                    "type": "integer",
                    "minimum": 0,
                    "maximum": FORECAST_DAYS - 1,
                    "description": "Days from today: today 0, tomorrow 1; leave empty for right now"
                    if english
                    else "Kaç gün sonrası: bugün 0, yarın 1; 'şu an' ya da gün söylenmediyse boş bırak",
                },
            },
        },
        refine=refine,
    )


def _hours(
    city: str, hourly: dict[str, Any], day: int, part: weather_request.PartOfDay, language: AssistantLanguage
) -> str | None:
    """The part of the day from Open-Meteo's hourly lists, which start at local midnight today."""
    first, last = weather_request.HOURS[part]
    window = slice(day * 24 + first, day * 24 + last)
    temperatures = [t for t in hourly.get("temperature_2m", [])[window] if t is not None]
    chances = [c for c in hourly.get("precipitation_probability", [])[window] if c is not None]
    if not temperatures:
        return None
    when = weather_report.period(_day_name(day, language), day, part, language)
    return weather_report.hourly(city, when, min(temperatures), max(temperatures), max(chances, default=0), language)


def _day_name(offset: int, language: AssistantLanguage) -> str:
    if offset == 0:
        return "today" if language is EN else "bugün"
    if offset == 1:
        return "tomorrow" if language is EN else "yarın"
    weekday = weekday_name(datetime.now() + timedelta(days=offset), language)
    return f"on {weekday}" if language is EN else text.lowercased(weekday)


CURRENCIES = {
    "TRY": ("lira", "lira"), "USD": ("dolar", "dollar"), "EUR": ("euro", "euro"), "GBP": ("sterlin", "pound"),
    "CHF": ("İsviçre frangı", "Swiss franc"), "JPY": ("yen", "yen"), "CNY": ("yuan", "yuan"),
    "CAD": ("Kanada doları", "Canadian dollar"), "AUD": ("Avustralya doları", "Australian dollar"),
    "SEK": ("İsveç kronu", "Swedish krona"), "NOK": ("Norveç kronu", "Norwegian krone"), "DKK": ("Danimarka kronu", "Danish krone"),
}  # fmt: skip


_TEXTS = {
    TR: {"gold": "Altın fiyatlarını henüz söyleyemiyorum; şimdilik yalnızca döviz kurlarını biliyorum."},
    EN: {"gold": "I can't tell gold prices yet; for now I only know exchange rates."},
}


def asks_for_gold(language: AssistantLanguage) -> Callable[[str], bool]:
    """ "Gram altın kaç lira": answered by rule, so no model treats gold as a currency or guesses a price."""
    return lambda command: currency_request.asks_for_gold(command, language is EN)


def exchange_rate(language: AssistantLanguage) -> Tool:
    english = language is EN

    def name(code: str) -> str:
        return CURRENCIES[code][1 if english else 0]

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        """Currencies and the amount said in the command win over the model's ("100 Euro kaç para" is 100)."""
        if currency_request.asks_for_gold(command, english):
            return {"gold": True}
        named = currency_request.currencies(command)
        said = currency_request.amount(command, english)
        refined = {**arguments, **({"amount": said} if said is not None else {})}
        if named:
            refined["from"] = named[0]
            # An unsaid target means lira to a Turkish speaker.
            refined["to"] = named[1] if len(named) > 1 else (None if english else "TRY")
        # In English an unsaid target is the dollar, or the euro for dollars.
        if not english or refined.get("to") not in (None, "TRY") or len(named) > 1:
            return refined
        words = text.folded(command).split()
        if any(w in words for w in ("lira", "try", "tl", "turkish")):
            return refined
        return {**refined, "to": "EUR" if refined.get("from") == "USD" else "USD"}

    def run(arguments: dict[str, Any]) -> str:
        if arguments.get("gold"):
            raise ToolError(_TEXTS[language]["gold"])
        source, target = arguments.get("from"), arguments.get("to") or ("USD" if english else "TRY")
        if source not in CURRENCIES or target not in CURRENCIES or source == target:
            raise ToolError(
                "I couldn't tell which currencies to convert."
                if english
                else "Hangi para birimini çevireceğimi anlayamadım."
            )
        amount = _amount(arguments.get("amount"))
        if amount is None:
            raise ToolError("I didn't get the amount." if english else "Miktarı anlayamadım.")
        try:
            data = _json(
                "https://api.frankfurter.app/latest?" + urlencode({"from": source, "to": target, "amount": amount}),
                language,
            )
        except web_fetch.WebFetchError as error:
            raise ToolError(
                ("Couldn't get the exchange rate. " if english else "Döviz kuru alınamadı. ")
                + web_fetch.describe(error, language)
            ) from error
        value = (data.get("rates") or {}).get(target)
        if value is None:
            raise ToolError("That rate isn't available." if english else "Bu kur bulunamadı.")
        return f"{_number(amount, language)} {name(source)} {_number(value, language)} {name(target)}."

    codes = sorted(CURRENCIES)
    return Tool(
        "exchangeRate",
        "Exchange rates and currency conversion: 'how much is the dollar in lira', '100 euros in dollars' (ECB rates)."
        if english
        else "Döviz kurunu ve para çevirisini söyler: 'dolar kaç lira', '100 euro kaç TL' (Avrupa Merkez Bankası kurları).",
        run=run,
        parameters={
            "type": "object",
            "properties": {
                "from": {"type": "string", "enum": codes},
                "to": {
                    "type": "string",
                    "enum": codes,
                    "description": "Target; leave empty if not said"
                    if english
                    else "Hedef para birimi; söylenmediyse TRY",
                },
                "amount": {
                    "type": "number",
                    "description": "Amount; leave empty if not said" if english else "Miktar; söylenmediyse boş bırak",
                },
            },
            "required": ["from"],
        },
        refine=refine,
    )


def _whole_number(value: Any) -> int | None:
    """Models send numbers as 1, 1.0 or "1"; anything else (including true/false) means not given."""
    if isinstance(value, bool):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return int(number) if math.isfinite(number) and number == int(number) else None


def _amount(value: Any) -> float | None:
    if value is None or value == "":
        return 1.0
    if isinstance(value, bool):
        return None
    try:
        number = float(str(value).replace(",", ".")) if isinstance(value, str) else float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) and number >= 0 else None


def _number(value: float, language: AssistantLanguage) -> str:
    """Up to two decimals, Turkish separators in Turkish: 1.234,5 / 1,234.5."""
    formatted = f"{value:,.2f}".rstrip("0").rstrip(".")
    if language is TR:
        formatted = formatted.replace(",", "\x00").replace(".", ",").replace("\x00", ".")
    return formatted


# As each feed names its topic.
NEWS_TOPIC_NAMES = {
    TR: {"economy": "ekonomi", "sports": "spor", "world": "dünya", "technology": "bilim-teknoloji"},
    EN: {"economy": "business", "sports": "sport", "world": "world", "technology": "technology"},
}


def _news_introduction(
    kind: news_request.Kind, category: str, source: news_source.NewsSource, language: AssistantLanguage
) -> str:
    name = NEWS_TOPIC_NAMES[language].get(category)
    if language is EN:
        if kind is news_request.Kind.NEXT:
            return "The next headlines. "
        if kind is news_request.Kind.AGAIN:
            return "Nothing new since I last read them; the latest are still these. "
        return f"Latest {name} headlines {source.from_}. " if name else f"Latest headlines {source.from_}. "
    if kind is news_request.Kind.NEXT:
        return "Sıradaki başlıklar. "
    if kind is news_request.Kind.AGAIN:
        return "Son okuduğumdan beri yeni başlık yok; en son başlıklar yine şunlar. "
    return f"{source.from_} son {name} başlıkları. " if name else f"{source.from_} son başlıklar. "


class NewsReading:
    """The headlines read out while Bilge runs, shared by the news and the tool that opens one of them."""

    def __init__(self) -> None:
        self._memory = news_request.HeadlineMemory()
        self._lock = threading.Lock()

    def recent_topic(self) -> str | None:
        with self._lock:
            return self._memory.recent_topic(datetime.now())

    def recent_source(self) -> news_source.NewsSource | None:
        with self._lock:
            found = self._memory.recent_source(datetime.now())
        return news_source.NewsSource(found) if found else None

    def next(
        self, items: list[rss_headlines.Item], topic: str, count: int, source: news_source.NewsSource
    ) -> news_request.Reading:
        with self._lock:
            return self._memory.next(items, topic, count, datetime.now(), source.value)

    def article(self, words: str, asked: bool = False) -> article_reference.Request | None:
        with self._lock:
            last, heard = self._memory.heard_items(datetime.now())
        return article_reference.find(words, last, heard, asked=asked)

    def was_read(self, link: str) -> rss_headlines.Item | None:
        with self._lock:
            _, heard = self._memory.heard_items(datetime.now())
        return next((item for item in heard if item.link == link), None)


def news(language: AssistantLanguage, reading: NewsReading | None = None) -> Tool:
    english = language is EN
    reading = reading or NewsReading()
    sources = news_source.sources(language)

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        """A topic or source said in the command wins over the model's choice; "bu kadar mı" goes on with what was
        just read, and "başka bir kaynak" turns to the next source."""
        continues = news_request.is_continuation(command)
        topic = news_request.topic(command) or (reading.recent_topic() if continues else None)
        topic = topic or str(arguments.get("category") or "general")
        source = news_source.named(command, language)
        if source is None and news_source.asks_for_another(command):
            source = (reading.recent_source() or news_source.preferred(language)).next(topic)
        elif source is None and continues:
            source = reading.recent_source()
        return {"category": topic, "source": source.value if source else None}

    def run(arguments: dict[str, Any]) -> str:
        category = arguments.get("category") or "general"
        if category not in news_request.TOPICS:
            category = "general"
        source = next((s for s in sources if s.value == arguments.get("source")), news_source.preferred(language))
        # A source without a feed of its own for the topic gives its general headlines, which the introduction says.
        if source.feed(category) is None:
            category = "general"
        try:
            feed = rss_headlines.items(web_fetch.get(source.feed(category) or "", language).body, FEED_COUNT)
        except web_fetch.WebFetchError as error:
            raise ToolError(
                ("Couldn't get the news. " if english else "Haberler alınamadı. ") + web_fetch.describe(error, language)
            ) from error
        if not feed:
            raise ToolError("No headlines found." if english else "Haber başlığı bulunamadı.")
        read = reading.next(feed, category, HEADLINE_COUNT, source)
        return _news_introduction(read.kind, category, source, language) + " ".join(
            h if h.endswith(".") else h + "." for h in read.headlines
        )

    return Tool(
        "news",
        "Reads the latest headlines: general, economy, sports, world or technology (BBC News, The Guardian or NPR)."
        if english
        else "Son haber başlıklarını okur: gündem, ekonomi, spor, dünya ya da bilim-teknoloji (Anadolu Ajansı, TRT "
        "Haber ya da BBC Türkçe).",
        run=run,
        parameters={
            "type": "object",
            "properties": {
                "category": {"type": "string", "enum": list(news_request.TOPICS)},
                "source": {"type": "string", "enum": [source.value for source in sources]},
            },
        },
        refine=refine,
        untrusted_output=True,
        spoken_action=lambda _: (
            "Shall I read the latest headlines?" if english else "Son haber başlıklarını okuyayım mı?"
        ),
    )


def news_source_rule_claims(language: AssistantLanguage, reading: NewsReading) -> Callable[[str], bool]:
    """ "Başka bir kaynak" after the headlines, and "TRT haberleri": routed to the news by rule, since a model may take
    the first for small talk."""

    def claims(command: str) -> bool:
        if news_source.asks_for_another(command):
            return reading.recent_topic() is not None
        return news_source.named(command, language) is not None and news_request.names_news(command)

    return claims


def news_article(
    language: AssistantLanguage,
    reading: NewsReading,
    open_link: Callable[[str], None] | None = None,
    text_reading: TextReading | None = None,
) -> Tool:
    """ "Claude'un keşfettiği buluşu aç", "üçüncü haberi anlat": one of the headlines just read, fetched for the model
    to tell in short; "aç" also shows it in the browser."""
    english = language is EN

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        arguments = continued(text_reading, arguments, command)
        if arguments.get("continue"):
            return arguments
        # The user's own words first; the model's paraphrase of them when those don't point at a headline.
        found = reading.article(command) or reading.article(str(arguments.get("headline") or ""), asked=True)
        if found is None:
            return {key: value for key, value in arguments.items() if key != "link"}
        return {**arguments, "link": found.item.link, "open": found.in_browser or bool(arguments.get("open"))}

    def run(arguments: dict[str, Any]) -> str:
        if arguments.get("continue") and text_reading is not None:
            return text_reading.more()
        item = reading.was_read(str(arguments.get("link") or ""))
        if item is None or item.link is None:
            raise ToolError(
                "I couldn't tell which story to open; could you name one of the headlines I read?"
                if english
                else "Hangi haberi açacağımı bulamadım; okuduğum başlıklardan birini söyler misin?"
            )
        opened = False
        if arguments.get("open") and open_link is not None:
            try:
                open_link(item.link)
                opened = True
            except Exception:  # noqa: BLE001 - without a browser the story is still told
                log.info("Could not open the story in the browser", exc_info=True)
        try:
            response = web_fetch.get(item.link, language)
            if not 200 <= response.status < 300:
                # A paywall, a bot block or a missing page is not the story.
                raise web_fetch.WebFetchError(web_fetch.Reason.STATUS, response.status)
        except web_fetch.WebFetchError as error:
            if opened:
                return f"Opened in the browser: {item.title}" if english else f"Haberi tarayıcıda açtım: {item.title}"
            raise ToolError(
                ("Couldn't open the story. " if english else "Haber açılamadı. ") + web_fetch.describe(error, language)
            ) from error
        body = _first_part(text_reading, item.title, html_text.extract(response.text()))
        note = ("(Opened in the browser.)\n" if english else "(Haber tarayıcıda açıldı.)\n") if opened else ""
        return f"{'Story' if english else 'Haber'}: {item.title}\n{note}\n{body}"

    return Tool(
        "newsArticle",
        "Opens one of the headlines just read out by the news tool and reads the story, to tell what it says."
        if english
        else "Haberler aracının az önce okuduğu başlıklardan birini açıp haberin kendisini okur; ne anlattığını söylemek için.",
        run=run,
        parameters={
            "type": "object",
            "properties": {
                "headline": {
                    "type": "string",
                    "description": "Which headline, as the user said it: its words or its place ('third', 'last')"
                    if english
                    else "Hangi başlık, kullanıcının dediği gibi: kelimeleri ya da sırası ('üçüncü', 'sonuncu')",
                },
                "open": {
                    "type": "boolean",
                    "description": "Also open it in the browser" if english else "Tarayıcıda da açılsın mı",
                },
            },
            "required": ["headline"],
        },
        refine=refine,
        untrusted_output=True,
        spoken_action=lambda _: "Shall I open that story?" if english else "Bu haberi açıp okuyayım mı?",
    )


def _first_part(text_reading: TextReading | None, title: str, body: str) -> str:
    if text_reading is None:
        return body[:PAGE_CHARACTERS]
    return text_reading.start(title, body, PAGE_CHARACTERS)


def read_web_page(language: AssistantLanguage, text_reading: TextReading | None = None) -> Tool:
    english = language is EN

    def run(arguments: dict[str, Any]) -> str:
        if arguments.get("continue") and text_reading is not None:
            return text_reading.more()
        address = str(arguments.get("address") or "").strip()
        if not address:
            raise ToolError("Which page?" if english else "Hangi sayfa?")
        url = address if "://" in address else f"https://{address}"
        try:
            response = web_fetch.get(url, language)
        except web_fetch.LocalAddressError as error:
            raise ToolError(web_fetch.describe(error, language)) from error
        except web_fetch.WebFetchError as error:
            raise ToolError(
                ("Couldn't open the page. " if english else "Sayfa açılamadı. ") + web_fetch.describe(error, language)
            ) from error
        page = response.text()
        title = html_text.title(page)
        body = _first_part(text_reading, title or address, html_text.extract(page))
        return f"{title}\n\n{body}" if title else body

    return Tool(
        "readWebPage",
        "Downloads and reads a web page at the given address, to summarize it or answer a question about it."
        if english
        else "Söylenen web adresindeki sayfayı indirip okur; özetlemek ya da soruyu yanıtlamak için.",
        run=run,
        parameters={
            "type": "object",
            "properties": {
                "address": {
                    "type": "string",
                    "description": "Web address, e.g. 'bbc.com'" if english else "Web adresi, örn. 'ntv.com.tr'",
                }
            },
            "required": ["address"],
        },
        refine=lambda arguments, command: continued(text_reading, arguments, command),
        untrusted_output=True,
        spoken_action=lambda a: (
            f"Shall I open and read {a.get('address') or 'the page'}?"
            if english
            else f"{a.get('address') or 'Sayfayı'} adresindeki sayfayı açıp okuyayım mı?"
        ),
    )
