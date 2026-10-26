"""Süper Lig from ESPN's public scoreboard: a team's score or next match, a day's results, this week's matches and
the table. No account or key."""

import logging
import re
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from typing import Any

from bilge.core import text
from bilge.core.language import AssistantLanguage
from bilge.core.web import football_report, football_teams, spoken_dates
from bilge.core.web.football_report import Match, State
from bilge.tools import web_fetch
from bilge.tools.base import Tool, ToolError
from bilge.tools.feed_cache import TimedCache, get_json

log = logging.getLogger(__name__)
EN = AssistantLanguage.ENGLISH

LEAGUE = "https://site.api.espn.com/apis/site/v2/sports/soccer/tur.1"
TABLE_URL = "https://site.api.espn.com/apis/v2/sports/soccer/tur.1/standings"
# "Bu hafta": a round runs from Friday to Monday, so the days around today rather than Monday to Sunday.
WEEK_BEFORE, WEEK_AFTER = 3, 3
TODAY_SECONDS, FUTURE_SECONDS, PAST_SECONDS = 60, 15 * 60, 60 * 60
TABLE_SECONDS, SCHEDULE_SECONDS, TEAMS_SECONDS = 10 * 60, 10 * 60, 24 * 60 * 60
REQUESTS = ("team", "day", "week", "table")

# Matched against folded text: recognizers spell Turkish letters either way, and "BIST" lowercases to "bıst".
_TABLE = re.compile(r"\b(puan durumu|puan tablosu|siralama\w*|kacinci|lider|standings|table|league position)\b")
_WEEK = re.compile(r"\b(bu hafta\w*|hafta ?sonu\w*|fikstur\w*|this week|weekend|fixtures)\b")
_NEXT = re.compile(r"\b(ne zaman|sonraki|siradaki|oynayacak\w*|when|next)\b")
_RESULTS = re.compile(r"\b(sonuc\w*|skor\w*|maclar\w*|results|scores|matches|games)\b")
_DAYS = (
    (re.compile(r"\b(dun|dunku|yesterdays?)\b"), -1),
    (re.compile(r"\b(bugun|bugunku|aksamki|todays?|tonights?)\b"), 0),
    (re.compile(r"\b(yarin|yarinki|tomorrows?)\b"), 1),
)
_LEAGUE = re.compile(r"\b(super lig\w*|puan durumu|mac sonuclari)\b")
_MATCH_WORDS = re.compile(
    r"\b(mac\w*|skor\w*|kac kac|oynuyor\w*|oynayacak\w*|gol\w*|score\w*|match\w*|game|playing|play)\b"
)


def read(command: str) -> dict[str, Any]:
    """The request as said: a team counts only when the command names it, not when the model fills one in."""
    lowered = text.folded(command)
    found = football_teams.mentioned(command)
    day = next((offset for pattern, offset in _DAYS if pattern.search(lowered)), None)
    if _TABLE.search(lowered):
        return {"request": "table", "team": found.name if found else ""}
    if found is not None:
        return {"request": "team", "team": found.name, "next": _NEXT.search(lowered) is not None}
    if _WEEK.search(lowered):
        return {"request": "week"}
    if day is not None or _RESULTS.search(lowered):
        return {"request": "day", "day_offset": day or 0}
    return {"request": "week"}


def asks_about_football(command: str) -> bool:
    """ "Galatasaray maçı kaç kaç", "puan durumu", "Süper Lig maçları": routed by rule, so no model answers a score
    from memory."""
    folded = text.folded(command)
    if _LEAGUE.search(folded):
        return True
    return football_teams.mentioned(command) is not None and _MATCH_WORDS.search(folded) is not None


def _local_now() -> datetime:
    return datetime.now().astimezone()


class League:
    """ESPN's Süper Lig data, each kind kept as long as it stays true."""

    def __init__(self, language: AssistantLanguage, clock: Callable[[], datetime], cache: TimedCache) -> None:
        self._language = language
        self._clock = clock
        self._cache = cache

    def _get(self, url: str, seconds: float) -> Any:
        return self._cache.get(url, seconds, lambda: get_json(url, self._language))

    def day(self, day: datetime) -> list[Match]:
        offset = (day.date() - self._clock().date()).days
        seconds = TODAY_SECONDS if offset == 0 else (FUTURE_SECONDS if offset > 0 else PAST_SECONDS)
        return football_report.parse_matches(self._get(f"{LEAGUE}/scoreboard?dates={day:%Y%m%d}", seconds))

    def days(self, days: list[datetime]) -> list[list[Match]]:
        with ThreadPoolExecutor(max_workers=len(days), thread_name_prefix="bilge-football") as pool:
            return list(pool.map(self.day, days))

    def table(self) -> list[football_report.Standing]:
        return football_report.parse_table(self._get(TABLE_URL, TABLE_SECONDS))

    def team_id(self, team: football_teams.Team) -> str | None:
        data = self._get(f"{LEAGUE}/teams", TEAMS_SECONDS)
        try:
            entries = data["sports"][0]["leagues"][0]["teams"]
        except (KeyError, IndexError, TypeError) as error:
            raise ValueError("ESPN sent no team list") from error
        for entry in entries:
            espn = entry.get("team") if isinstance(entry, dict) else None
            if isinstance(espn, dict) and football_teams.from_espn(str(espn.get("displayName", ""))) == team:
                return str(espn.get("id"))
        return None

    def schedule(self, team_id: str, upcoming: bool) -> list[Match]:
        url = f"{LEAGUE}/teams/{team_id}/schedule" + ("?fixture=true" if upcoming else "")
        return football_report.parse_matches(self._get(url, SCHEDULE_SECONDS))


def football(
    language: AssistantLanguage, clock: Callable[[], datetime] = _local_now, cache: TimedCache | None = None
) -> Tool:
    english = language is EN
    league = League(language, clock, cache or TimedCache())

    def run(arguments: dict[str, Any]) -> str:
        request = arguments.get("request") if arguments.get("request") in REQUESTS else "week"
        team = football_teams.named(str(arguments.get("team") or "")) if arguments.get("team") else None
        try:
            if request == "table":
                return football_report.table(league.table(), language, team.name if team else None)
            if request == "team" and team is not None:
                return _team(league, team, bool(arguments.get("next")), clock(), language)
            if request == "day":
                return _day(league, _offset(arguments.get("day_offset")), clock(), language)
            return _week(league, clock(), language)
        except ValueError as error:
            log.info("ESPN's answer didn't read: %s", error)
            raise _failed(web_fetch.WebFetchError(web_fetch.Reason.UNEXPECTED), language) from error
        except web_fetch.WebFetchError as error:
            raise _failed(error, language) from error

    return Tool(
        "football",
        "Süper Lig (Turkish football league): a team's score or live minute, when it plays next, a day's results, this "
        "week's matches, the table."
        if english
        else "Süper Lig: bir takımın maçı kaç kaç ya da kaçıncı dakikada, ne zaman oynayacağı, bir günün maç sonuçları, "
        "bu haftanın maçları, puan durumu.",
        run=run,
        parameters={
            "type": "object",
            "properties": {
                "request": {"type": "string", "enum": list(REQUESTS)},
                "team": {
                    "type": "string",
                    "description": "Team as said, e.g. 'Galatasaray', 'FB'; leave empty if none"
                    if english
                    else "Söylenen takım, örn. 'Galatasaray', 'FB'; söylenmediyse boş bırak",
                },
                "next": {"type": "boolean", "description": "Asks when it plays next" if english else "Ne zaman oynayacağı soruluyor"},
                "day_offset": {"type": "integer", "description": "Yesterday -1, today 0, tomorrow 1" if english else "Dün -1, bugün 0, yarın 1"},
            },
        },
        refine=lambda _, command: read(command),
    )  # fmt: skip


def _failed(error: web_fetch.WebFetchError, language: AssistantLanguage) -> ToolError:
    lead = "Couldn't get the football results. " if language is EN else "Maç bilgisi alınamadı. "
    return ToolError(lead + web_fetch.describe(error, language))


def _offset(value: Any) -> int:
    try:
        return max(-7, min(7, int(value)))
    except (TypeError, ValueError):
        return 0


def _team(
    league: League, team: football_teams.Team, wants_next: bool, now: datetime, language: AssistantLanguage
) -> str:
    """Today's match if there is one (the score, the minute, or the kick-off); otherwise the last result and the
    next match. "Ne zaman oynuyor" gives the next one, and a match on right now as well."""
    english = language is EN
    today = next((m for m in league.day(now) if m.involves(team.name)), None)
    if today is not None and not wants_next:
        return football_report.describe(today, now, language) + "."
    team_id = league.team_id(team)
    if team_id is None:
        return (
            f"{team.name} isn't in this season's Süper Lig." if english else f"{team.name} bu sezon Süper Lig'de yok."
        )
    told = [football_report.describe(today, now, language)] if today is not None and today.state is State.LIVE else []
    if not wants_next:
        played = [m for m in league.schedule(team_id, upcoming=False) if m.state is State.FINISHED]
        if played:
            last = football_report.describe(played[-1], now, language)
            told.append(f"Last match: {last}" if english else f"Son maç: {last}")
    coming = [m for m in league.schedule(team_id, upcoming=True) if m.state is State.SCHEDULED and m.kickoff > now]
    if coming:
        upcoming = football_report.describe(coming[0], now, language)
        told.append(upcoming if wants_next else (f"Next: {upcoming}" if english else f"Sıradaki: {upcoming}"))
    if not told:
        return (
            f"I found no Süper Lig match for {team.name}." if english else f"{team.name} için Süper Lig maçı bulamadım."
        )
    return ". ".join(told) + "."


def _first_upper(phrase: str) -> str:
    return phrase[:1].upper() + phrase[1:]


def _day(league: League, offset: int, now: datetime, language: AssistantLanguage) -> str:
    english = language is EN
    day = now + timedelta(days=offset)
    matches = league.day(day)
    when = spoken_dates.day_phrase(day, now, language)
    if not matches:
        return f"No Süper Lig matches {when}." if english else f"{_first_upper(when)} Süper Lig maçı yok."
    listed = "; ".join(football_report.describe(m, now, language, with_day=False) for m in matches)
    return f"Süper Lig {when}: {listed}." if english else f"{_first_upper(when)} Süper Lig: {listed}."


def _week(league: League, now: datetime, language: AssistantLanguage) -> str:
    english = language is EN
    days = [now + timedelta(days=offset) for offset in range(-WEEK_BEFORE, WEEK_AFTER + 1)]
    told = []
    for day, matches in zip(days, league.days(days), strict=True):
        if matches:
            listed = "; ".join(football_report.describe(m, now, language, with_day=False) for m in matches)
            told.append(f"{_first_upper(spoken_dates.day_phrase(day, now, language))}: {listed}.")
    if not told:
        return "No Süper Lig matches this week." if english else "Bu hafta Süper Lig maçı yok."
    return ("Süper Lig this week. " if english else "Bu hafta Süper Lig. ") + " ".join(told)
