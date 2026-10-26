"""Prayer times from Diyanet's monthly table (ezanvakti.emushaf.net), with Aladhan's Diyanet method when that
fails. Neither needs an account or a key."""

import threading
from collections.abc import Callable
from datetime import date, datetime, timedelta, timezone
from typing import Any
from urllib.parse import quote, urlencode

from bilge.brain.instructions import weekday_name
from bilge.core import text
from bilge.core.language import AssistantLanguage
from bilge.core.tools import english_time_parser, relative_day_parser
from bilge.core.web import prayer_answer, prayer_times, turkish_provinces
from bilge.core.web.prayer_times import DayTimes, Occasion, Question, Vakit
from bilge.tools import web_fetch
from bilge.tools.base import Tool, ToolError

EN = AssistantLanguage.ENGLISH
# Turkey keeps UTC+3 all year; the tables are in local time there whatever this computer's zone is.
TURKEY = timezone(timedelta(hours=3))
EZANVAKTI = "https://ezanvakti.emushaf.net"
# The country id of Turkey in ezanvakti's list.
EZANVAKTI_TURKEY = 2
ALADHAN = "https://api.aladhan.com/v1/timingsByCity/"
ALADHAN_DIYANET = 13
MAX_DAY_OFFSET = 6


class PrayerTimesSource:
    """Times per city, kept while Bilge runs: the province list, each centre's id and its month of times are fetched
    once, since ezanvakti answers too many requests with 429."""

    def __init__(self, language: AssistantLanguage) -> None:
        self._language = language
        self._lock = threading.Lock()
        self._cities: Any = None
        self._centres: dict[int, str] = {}
        self._days: dict[str, dict[date, DayTimes]] = {}

    def days(self, city: str, wanted: list[date]) -> dict[date, DayTimes]:
        """Raises the fetch error when some wanted day can't be had from either source."""
        key = text.folded(city)
        with self._lock:
            known = self._days.get(key, {})
        if all(day in known for day in wanted):
            return known
        failure: web_fetch.WebFetchError | None = None
        province = turkish_provinces.find(city)
        if province is not None:
            try:
                known = {**known, **self._diyanet(province)}
            except web_fetch.WebFetchError as error:
                failure = error
        for day in [d for d in wanted if d not in known]:
            try:
                found = self._aladhan(province.name if province else city, day)
            except web_fetch.WebFetchError as error:
                failure = failure or error
                continue
            if found is not None:
                known = {**known, found.day: found}
        with self._lock:
            self._days = {**self._days, key: known}
        if any(day not in known for day in wanted):
            raise failure or web_fetch.WebFetchError(web_fetch.Reason.UNEXPECTED)
        return known

    def _diyanet(self, province: turkish_provinces.Province) -> dict[date, DayTimes]:
        centre = self._centres.get(province.plate)
        if centre is None:
            if self._cities is None:
                self._cities = web_fetch.get_json(f"{EZANVAKTI}/sehirler/{EZANVAKTI_TURKEY}", self._language)
            city_id = prayer_times.province_id(self._cities, province.name)
            if city_id is None:
                return {}
            districts = web_fetch.get_json(f"{EZANVAKTI}/ilceler/{quote(city_id)}", self._language)
            centre = prayer_times.centre_id(districts, province.name)
            if centre is None:
                return {}
            self._centres = {**self._centres, province.plate: centre}
        return prayer_times.from_ezanvakti(web_fetch.get_json(f"{EZANVAKTI}/vakitler/{quote(centre)}", self._language))

    def _aladhan(self, city: str, day: date) -> DayTimes | None:
        query = urlencode({"city": city, "country": "Turkey", "method": ALADHAN_DIYANET})
        found = prayer_times.from_aladhan(web_fetch.get_json(f"{ALADHAN}{day:%d-%m-%Y}?{query}", self._language))
        return found if found is not None and found.day == day else None


def prayer_times_tool(
    language: AssistantLanguage,
    default_city: Callable[[], str],
    source: PrayerTimesSource | None = None,
    clock: Callable[[], datetime] = lambda: datetime.now(TURKEY),
) -> Tool:
    english = language is EN
    source = source or PrayerTimesSource(language)
    vakits = [vakit.value for vakit in Vakit]

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        """What was said wins: a city only if named, the vakit, the day and whether the time left was asked."""
        province = turkish_provinces.find(command)
        city = str(arguments.get("city") or "").strip()
        if city and not any(w.startswith(text.folded(city)[:4]) for w in text.folded(command).split()):
            city = ""
        parser = english_time_parser if english else relative_day_parser
        offset = parser.day_offset(command, clock())
        asked = prayer_times.question(command, english, offset if offset and 0 < offset <= MAX_DAY_OFFSET else 0)
        vakit = (
            asked.vakit.value if asked.vakit else (arguments.get("vakit") if arguments.get("vakit") in vakits else None)
        )
        return {
            "city": province.name if province else city or None,
            "vakit": vakit,
            "occasion": asked.occasion.value if asked.occasion else None,
            "day_offset": asked.day_offset,
            "whole_day": asked.whole_day or (vakit is None and bool(arguments.get("whole_day"))),
            "remaining": asked.remaining,
        }

    def run(arguments: dict[str, Any]) -> str:
        city = str(arguments.get("city") or "").strip() or default_city()
        province = turkish_provinces.find(city)
        place = province.name if province else city
        asked = _question(arguments)
        now = clock()
        day = now.date() + timedelta(days=asked.day_offset)
        wanted = [day] if asked.whole_day or asked.day_offset else [day, day + timedelta(days=1)]
        try:
            days = source.days(place, wanted)
        except web_fetch.WebFetchError as error:
            raise ToolError(
                ("Couldn't get the prayer times. " if english else "Namaz vakitleri alınamadı. ")
                + web_fetch.describe(error, language)
            ) from error
        told = prayer_answer.answer(days, now, place, asked, _day_name(asked.day_offset, day, language), language)
        if told is None:
            raise ToolError("Couldn't get the prayer times." if english else "Namaz vakitleri alınamadı.")
        return told

    return Tool(
        "prayerTimes",
        "Prayer times in Turkey (Diyanet): a given prayer such as maghrib or fajr, the next one and the time left, "
        "iftar and suhoor, or the whole day's times, today or on a coming day."
        if english
        else "Namaz vakitlerini söyler (Diyanet): akşam, imsak gibi bir vakit, sıradaki vakit ve kalan süre, iftar ve "
        "sahur, ya da günün bütün vakitleri; bugün ya da önümüzdeki bir gün.",
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
                "vakit": {
                    "type": "string",
                    "enum": vakits,
                    "description": "The prayer asked about; leave empty for the next one"
                    if english
                    else "Sorulan vakit (iftar: aksam, sahur: imsak); sıradaki vakit soruluyorsa boş bırak",
                },
                "whole_day": {
                    "type": "boolean",
                    "description": "All of the day's times" if english else "Günün bütün vakitleri",
                },
            },
        },
        refine=refine,
    )


def _question(arguments: dict[str, Any]) -> Question:
    try:
        vakit = Vakit(arguments.get("vakit")) if arguments.get("vakit") else None
        occasion = Occasion(arguments.get("occasion")) if arguments.get("occasion") else None
    except ValueError:
        vakit, occasion = None, None
    offset = arguments.get("day_offset")
    offset = offset if isinstance(offset, int) and not isinstance(offset, bool) else 0
    offset = min(max(offset, 0), MAX_DAY_OFFSET)
    # "Yarın ezan vakitleri" with no vakit named is the whole day.
    whole_day = (bool(arguments.get("whole_day")) or offset > 0) and vakit is None
    return Question(vakit, occasion, offset, whole_day, bool(arguments.get("remaining")))


def _day_name(offset: int, day: date, language: AssistantLanguage) -> str:
    if offset == 0:
        return "today" if language is EN else "bugün"
    if offset == 1:
        return "tomorrow" if language is EN else "yarın"
    weekday = weekday_name(datetime.combine(day, datetime.min.time()), language)
    return f"on {weekday}" if language is EN else text.lowercased(weekday)


def asks_for_prayer_times(language: AssistantLanguage) -> Callable[[str], bool]:
    """ "Akşam ezanı kaçta", "iftara ne kadar var": routed by rule, so no model guesses a time."""
    return lambda command: prayer_times.claims(command, language is EN)
