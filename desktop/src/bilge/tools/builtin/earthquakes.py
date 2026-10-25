"""Earthquakes in and around Türkiye: answering questions about them, and saying it unasked when a strong one
happens near the user's city. AFAD first, Kandilli Observatory when AFAD can't be reached."""

import logging
import re
import threading
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any
from urllib.parse import urlencode

from bilge.core import text
from bilge.core.alerts import earthquake_alert
from bilge.core.language import AssistantLanguage
from bilge.core.web import earthquake_feed, earthquake_report, provinces
from bilge.core.web.earthquake_feed import Earthquake
from bilge.tools import web_fetch
from bilge.tools.base import Tool, ToolError
from bilge.tools.feed_cache import TimedCache, get_json

log = logging.getLogger(__name__)
EN = AssistantLanguage.ENGLISH

AFAD_URL = "https://servisnet.afad.gov.tr/apigateway/deprem/apiv2/event/filter"
# The observatory serves the list over plain HTTP only.
KANDILLI_URL = "http://www.koeri.boun.edu.tr/scripts/lst0.asp"
CACHE_SECONDS = 60
# The alert asks for a short window, so the answer is small every two minutes.
ALERT_WINDOW = timedelta(hours=2)

# Folded words; a question about earthquakes that happened, not "deprem çantası nasıl hazırlanır".
_QUAKE = re.compile(r"\b(deprem\w*|earthquakes?|quakes?)\b")
_HAPPENED = re.compile(
    r"\b(oldu\w*|olmus\w*|var mi|nerede|son|sallan\w*|buyuk\w*|kac|any|latest|recent|last|today|was there|"
    r"were there|happen\w*|near)\b"
)

_SOURCE_NAMES = {
    "afad": {AssistantLanguage.TURKISH: "AFAD", EN: "AFAD"},
    "kandilli": {AssistantLanguage.TURKISH: "Kandilli Rasathanesi", EN: "Kandilli Observatory"},
}


def recent(language: AssistantLanguage, since: datetime, minimum: float, now: datetime) -> tuple[list[Earthquake], str]:
    """The earthquakes since `since` of at least `minimum`, newest first, and which source gave them."""
    query = {
        "start": since.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%S"),
        "end": (now.astimezone(UTC) + timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%S"),
        "minmag": f"{minimum:g}",
        "format": "json",
    }
    try:
        response = web_fetch.get(f"{AFAD_URL}?{urlencode(query)}", language)
        if response.status != 200:
            raise web_fetch.WebFetchError(web_fetch.Reason.STATUS, response.status)
        quakes, source = earthquake_feed.parse_afad(response.body), "afad"
    except (web_fetch.WebFetchError, ValueError) as error:
        log.info("AFAD's earthquake list failed (%s); trying Kandilli", error)
        quakes, source = _kandilli(language), "kandilli"
    return [q for q in quakes if q.time >= since and q.magnitude >= minimum], source


def _kandilli(language: AssistantLanguage) -> list[Earthquake]:
    response = web_fetch.get(KANDILLI_URL, language)
    if response.status != 200:
        raise web_fetch.WebFetchError(web_fetch.Reason.STATUS, response.status)
    quakes = earthquake_feed.parse_kandilli(response.body)
    if not quakes:
        # The table always lists the last 500; none means the page changed.
        raise web_fetch.WebFetchError(web_fetch.Reason.UNEXPECTED)
    return quakes


def asks_about_earthquakes(command: str) -> bool:
    """ "Deprem oldu mu", "son depremler": by rule, so no model answers from memory that it can't know."""
    folded = text.folded(command)
    return _QUAKE.search(folded) is not None and _HAPPENED.search(folded) is not None


def _local_now() -> datetime:
    return datetime.now().astimezone()


def earthquakes(
    language: AssistantLanguage,
    home_city: Callable[[], str],
    clock: Callable[[], datetime] = _local_now,
    cache: TimedCache | None = None,
) -> Tool:
    english = language is EN
    cache = cache or TimedCache()

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        """What is asked comes from the words said: a local model once turned "deprem oldu mu" into big ones only."""
        query = earthquake_report.read(command, str(arguments.get("place") or ""))
        place = query.province.name if query.province else query.place
        return {"place": place, "today": query.today, "big": query.big, "latest": query.latest}

    def run(arguments: dict[str, Any]) -> str:
        place = str(arguments.get("place") or "").strip()
        province = provinces.named(place) if place else None
        query = earthquake_report.Query(
            province=province,
            place="" if province else place,
            today=bool(arguments.get("today")),
            big=bool(arguments.get("big")),
            latest=bool(arguments.get("latest")),
        )
        now = clock()
        since = now - timedelta(hours=earthquake_report.RECENT_HOURS)
        try:
            quakes, source = cache.get(
                "day",
                CACHE_SECONDS,
                lambda: recent(language, since, earthquake_report.LISTED_MAGNITUDE, now),
            )
        except web_fetch.WebFetchError as error:
            raise ToolError(
                ("Couldn't get the earthquake list. " if english else "Deprem bilgisi alınamadı. ")
                + web_fetch.describe(error, language)
            ) from error
        chosen = earthquake_report.select(quakes, query, now)
        home = provinces.named(home_city())
        return earthquake_report.answer(chosen, query, now, language, home, _SOURCE_NAMES[source][language])

    return Tool(
        "earthquakes",
        "Recent earthquakes in and around Türkiye (AFAD, Kandilli): the latest ones, near a city, today's big ones, "
        "where the last one was."
        if english
        else "Türkiye ve çevresindeki son depremleri söyler (AFAD, Kandilli): son depremler, bir şehrin yakınında "
        "deprem olup olmadığı, bugünkü büyük depremler, en son depremin yeri.",
        run=run,
        parameters={
            "type": "object",
            "properties": {
                "place": {
                    "type": "string",
                    "description": "City or district only; leave empty if none was said"
                    if english
                    else "Şehir ya da ilçe adı, eksiz: 'İzmir'de' → 'İzmir'; söylenmediyse boş bırak",
                }
            },
        },
        refine=refine,
    )


def locate_city(city: str, language: AssistantLanguage) -> provinces.Place | None:
    """A province from the table, otherwise Open-Meteo's geocoding (the same as the weather uses)."""
    found = provinces.named(city)
    if found is not None or not city.strip():
        return found
    places = get_json(
        "https://geocoding-api.open-meteo.com/v1/search?" + urlencode({"name": city, "count": 1}), language
    )
    first = (places.get("results") or [None])[0] if isinstance(places, dict) else None
    try:
        return provinces.Place(str(first["name"]), float(first["latitude"]), float(first["longitude"]))
    except (TypeError, KeyError, ValueError):
        return None


def alert_message(quake: Earthquake, now: datetime, home: provinces.Place, language: AssistantLanguage) -> str:
    described = earthquake_report.describe(quake, now, language, home)
    return f"Earthquake nearby: {described}." if language is EN else f"Yakınında deprem: {described}."


class EarthquakeWatcher:
    """While Bilge runs, looks every two minutes for a strong earthquake near the user's city and says it once.
    Errors push the next look further out instead of knocking on a failing service every two minutes."""

    def __init__(
        self,
        language: AssistantLanguage,
        city: Callable[[], str],
        alert: Callable[[str], None],
        announced: earthquake_alert.Announced | None = None,
        fetch: Callable[[datetime, datetime], list[Earthquake]] | None = None,
        locate: Callable[[str], provinces.Place | None] | None = None,
        clock: Callable[[], datetime] = _local_now,
    ) -> None:
        self._language = language
        self._city = city
        self._alert = alert
        self._announced = announced or earthquake_alert.Announced()
        self._fetch = fetch or (lambda since, now: recent(language, since, earthquake_alert.ALERT_MAGNITUDE, now)[0])
        self._locate = locate or (lambda name: locate_city(name, language))
        self._clock = clock
        self._alerts: earthquake_alert.EarthquakeAlerts | None = None
        self._failures = 0
        self._stopped = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if self._thread is not None:
            return
        # Each run has its own flag, so a run being stopped can't be revived by the next start.
        self._stopped = threading.Event()
        self._thread = threading.Thread(
            target=self._watch, args=(self._stopped,), name="bilge-earthquakes", daemon=True
        )
        self._thread.start()

    def stop(self) -> None:
        self._stopped.set()
        self._thread = None

    def poll(self) -> float:
        """One look; returns the seconds to wait before the next."""
        try:
            alerts = self._alerts or self._make_alerts()
            if alerts is None:
                log.warning("Can't place %r on the map; earthquake alerts are off", self._city())
                return earthquake_alert.MAX_RETRY_SECONDS
            now = self._clock()
            quakes = self._fetch(now - ALERT_WINDOW, now)
        except (web_fetch.WebFetchError, ValueError) as error:
            self._failures += 1
            delay = earthquake_alert.retry_delay(self._failures)
            log.info("Earthquake check failed (%s); next in %.0f s", error, delay)
            return delay
        self._failures = 0
        for quake in alerts.due(quakes, now):
            self._say(alert_message(quake, now, alerts.home, self._language))
        return earthquake_alert.POLL_SECONDS

    def _make_alerts(self) -> earthquake_alert.EarthquakeAlerts | None:
        home = self._locate(self._city())
        if home is not None:
            self._alerts = earthquake_alert.EarthquakeAlerts(home, self._announced)
        return self._alerts

    def _watch(self, stopped: threading.Event) -> None:
        delay = 0.0
        while not stopped.wait(delay):
            try:
                delay = self.poll()
            except Exception:  # noqa: BLE001 - an unforeseen error must not end the watching for the rest of the run
                log.exception("Earthquake check crashed")
                delay = earthquake_alert.MAX_RETRY_SECONDS

    def _say(self, message: str) -> None:
        try:
            self._alert(message)
        except Exception:  # noqa: BLE001 - a failed announcement must not stop the watching
            log.exception("Announcing an earthquake failed")
