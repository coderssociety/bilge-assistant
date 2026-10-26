"""Süper Lig matches and the table from ESPN's JSON, and how Bilge says them: the score and minute of a match being
played, a result, a kick-off time, the top of the table."""

import logging
import re
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Any

from bilge.core import text
from bilge.core.language import AssistantLanguage
from bilge.core.web.football_teams import display_name
from bilge.core.web.spoken_dates import day_phrase

log = logging.getLogger(__name__)
EN = AssistantLanguage.ENGLISH
TABLE_COUNT = 5


class State(StrEnum):
    SCHEDULED = "pre"
    LIVE = "in"
    FINISHED = "post"


@dataclass(frozen=True)
class Match:
    id: str
    kickoff: datetime
    home: str
    away: str
    home_score: int | None
    away_score: int | None
    state: State
    # ESPN's clock: "67'", "45'+6'".
    clock: str = ""
    status: str = ""

    def involves(self, team_name: str) -> bool:
        return team_name in (self.home, self.away)


def parse_matches(data: Any) -> list[Match]:
    """Events from the scoreboard or a team's schedule; the two put the status and the score in different places."""
    events = data.get("events") if isinstance(data, dict) else None
    if not isinstance(events, list):
        raise ValueError("ESPN sent no list of matches")
    found = [match for event in events if isinstance(event, dict) and (match := _match(event)) is not None]
    return sorted(found, key=lambda m: m.kickoff)


def _match(event: dict[str, Any]) -> Match | None:
    try:
        competition = event["competitions"][0]
        sides = {side["homeAway"]: side for side in competition["competitors"]}
        home, away = sides["home"], sides["away"]
        kickoff = datetime.fromisoformat(str(event["date"]).replace("Z", "+00:00"))
        status = event.get("status") or competition.get("status") or {}
        kind = status.get("type") or {}
        state = State(kind.get("state", "pre"))
    except (KeyError, IndexError, TypeError, ValueError):
        log.debug("Skipped an ESPN event: %r", event.get("id"))
        return None
    return Match(
        id=str(event.get("id", "")),
        kickoff=kickoff,
        home=display_name(str(home["team"].get("displayName", ""))),
        away=display_name(str(away["team"].get("displayName", ""))),
        home_score=_score(home.get("score")) if state is not State.SCHEDULED else None,
        away_score=_score(away.get("score")) if state is not State.SCHEDULED else None,
        state=state,
        clock=str(status.get("displayClock") or ""),
        status=str(kind.get("name") or ""),
    )


def _score(value: Any) -> int | None:
    if isinstance(value, dict):
        value = value.get("displayValue", value.get("value"))
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


@dataclass(frozen=True)
class Standing:
    rank: int
    team: str
    points: int
    played: int


def parse_table(data: Any) -> list[Standing]:
    try:
        entries = data["children"][0]["standings"]["entries"]
    except (KeyError, IndexError, TypeError) as error:
        raise ValueError("ESPN sent no table") from error
    table = []
    for entry in entries:
        try:
            stats = {stat["name"]: stat.get("value", stat.get("displayValue")) for stat in entry["stats"]}
            table.append(Standing(int(float(stats["rank"])), display_name(str(entry["team"]["displayName"])),
                                  int(float(stats["points"])), int(float(stats["gamesPlayed"]))))  # fmt: skip
        except (KeyError, TypeError, ValueError):
            log.debug("Skipped a table row")
    if not table:
        raise ValueError("ESPN sent an empty table")
    return sorted(table, key=lambda s: s.rank)


def describe(match: Match, now: datetime, language: AssistantLanguage, with_day: bool = True) -> str:
    """ "Galatasaray 1, Fenerbahçe 0, 67. dakika" / "Galatasaray - Fenerbahçe maçı yarın saat 21:30'da"."""
    english = language is EN
    local = match.kickoff.astimezone(now.tzinfo)
    day = day_phrase(local, now, language)
    if match.status in ("STATUS_POSTPONED", "STATUS_CANCELED", "STATUS_ABANDONED"):
        called_off = "postponed" if match.status == "STATUS_POSTPONED" else "called off"
        if english:
            return f"{match.home} v {match.away} ({day}): {called_off}"
        return f"{match.home} - {match.away} ({day}): {'ertelendi' if called_off == 'postponed' else 'iptal edildi'}"
    if match.state is State.SCHEDULED or match.home_score is None or match.away_score is None:
        if english:
            return f"{match.home} v {match.away}" + (f", {day} at {local:%H:%M}" if with_day else f" at {local:%H:%M}")
        when = f"{day} saat " if with_day else "saat "
        return f"{match.home} - {match.away} maçı {when}{text.time_locative(local.hour, local.minute)}"
    score = f"{match.home} {match.home_score}, {match.away} {match.away_score}"
    if match.state is State.LIVE:
        return f"{score}, {_live(match, english)}"
    if english:
        return f"{score}, full time" + (f" ({day})" if with_day else "")
    return f"{score}, maç bitti" + (f" ({day})" if with_day else "")


def _live(match: Match, english: bool) -> str:
    if match.status == "STATUS_HALFTIME":
        return "half-time" if english else "devre arası"
    minute = re.sub(r"[^\d+]", "", match.clock)
    if not minute:
        return "being played" if english else "maç sürüyor"
    return f"minute {minute}" if english else f"{minute}. dakika"


def table(standings: list[Standing], language: AssistantLanguage, team: str | None = None) -> str:
    """The top of the table, or where the team asked about stands and who leads."""
    english = language is EN
    found = next((s for s in standings if s.team == team), None)
    if found is not None:
        leader = standings[0]
        if english:
            spoken = f"{found.team} is {_ordinal(found.rank)} with {found.points} points from {found.played} games."
            return spoken + ("" if leader == found else f" {leader.team} leads with {leader.points}.")
        spoken = f"{found.team} {found.played} maçta {found.points} puanla {found.rank}. sırada."
        return spoken + ("" if leader == found else f" Lider {leader.team}, {leader.points} puan.")
    top = standings[:TABLE_COUNT]
    if english:
        return "Süper Lig table: " + ", ".join(f"{s.rank} {s.team} {s.points} points" for s in top) + "."
    return "Süper Lig puan durumu: " + ", ".join(f"{s.rank}. {s.team} {s.points} puan" for s in top) + "."


def _ordinal(number: int) -> str:
    suffix = "th" if 10 <= number % 100 <= 20 else {1: "st", 2: "nd", 3: "rd"}.get(number % 10, "th")
    return f"{number}{suffix}"
