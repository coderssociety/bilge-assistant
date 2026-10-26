from datetime import UTC, datetime, timedelta, timezone

import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.web import football_report, football_teams
from bilge.core.web.football_report import Match, State

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
NOW = datetime(2026, 10, 25, 19, 30, tzinfo=timezone(timedelta(hours=3)))


def event(id, date, home, away, state, home_score=None, away_score=None, clock="", name="", in_competition=False):
    status = {"displayClock": clock, "type": {"state": state, "name": name}}
    sides = [{"homeAway": "home", "team": {"displayName": home}, "score": home_score},
             {"homeAway": "away", "team": {"displayName": away}, "score": away_score}]  # fmt: skip
    competition = {"competitors": sides, **({"status": status} if in_competition else {})}
    return {"id": id, "date": date, "competitions": [competition], **({} if in_competition else {"status": status})}


SCOREBOARD = {
    "events": [
        event("3", "2026-10-25T16:00Z", "Goztepe", "Çorum FK", "in", "2", "0", "45'+6'", "STATUS_HALFTIME"),
        event("1", "2026-10-25T13:00Z", "Konyaspor", "Genclerbirligi", "post", "2", "0", "90'+5'", "STATUS_FULL_TIME"),
        event("4", "2026-10-25T17:00Z", "Istanbul Basaksehir", "Besiktas", "in", "1", "1", "67'", "STATUS_SECOND_HALF"),
        event("5", "2026-10-26T18:30Z", "Galatasaray", "Fenerbahce", "pre", "0", "0", "0'", "STATUS_SCHEDULED"),
        {"id": "broken"},
    ]
}  # fmt: skip


@pytest.mark.parametrize(
    ("command", "team"),
    [
        ("Galatasaray maçı kaç kaç", "Galatasaray"),
        ("GS'nin maçı ne zaman", "Galatasaray"),
        ("Cimbom bugün oynuyor mu", "Galatasaray"),
        ("Fener ne zaman oynuyor", "Fenerbahçe"),
        ("fenerbahçenin maçı", "Fenerbahçe"),
        ("BJK maçı kaç kaç", "Beşiktaş"),
        ("TS maçı", "Trabzonspor"),
        ("Trabzonspor maçı", "Trabzonspor"),
        ("Başakşehir maçı", "Başakşehir"),
        ("when does Besiktas play", "Beşiktaş"),
        ("bu hafta maçlar", None),
        ("puan durumu", None),
    ],
)
def test_teams_by_the_names_fans_use(command, team):
    found = football_teams.mentioned(command)
    assert (found.name if found else None) == team


def test_espn_names_become_turkish_ones():
    assert football_teams.display_name("Istanbul Basaksehir") == "Başakşehir"
    assert football_teams.display_name("Erzurum BB") == "Erzurumspor"
    assert football_teams.display_name("Some New Club") == "Some New Club"
    assert football_teams.named("FB").name == "Fenerbahçe"


def test_the_scoreboard_is_read_in_kickoff_order():
    matches = football_report.parse_matches(SCOREBOARD)
    assert [m.id for m in matches] == ["1", "3", "4", "5"]
    konya = matches[0]
    assert (konya.home, konya.away, konya.home_score, konya.away_score) == ("Konyaspor", "Gençlerbirliği", 2, 0)
    assert matches[3].home_score is None and matches[3].state is State.SCHEDULED


def test_a_team_schedule_keeps_status_and_score_elsewhere():
    played = event("9", "2026-10-17T16:00Z", "Fenerbahce", "Alanyaspor", "post", {"value": 3.0, "displayValue": "3"},
                   {"value": 0.0, "displayValue": "0"}, name="STATUS_FULL_TIME", in_competition=True)  # fmt: skip
    (match,) = football_report.parse_matches({"events": [played]})
    assert (match.home, match.home_score, match.away_score, match.state) == ("Fenerbahçe", 3, 0, State.FINISHED)


def test_no_list_of_matches_is_an_error():
    with pytest.raises(ValueError):
        football_report.parse_matches({"code": 400})


def test_matches_as_spoken():
    konya, goztepe, basaksehir, derby = football_report.parse_matches(SCOREBOARD)
    say = football_report.describe
    assert say(goztepe, NOW, TR) == "Göztepe 2, Çorum FK 0, devre arası"
    assert say(basaksehir, NOW, TR) == "Başakşehir 1, Beşiktaş 1, 67. dakika"
    assert say(konya, NOW, TR) == "Konyaspor 2, Gençlerbirliği 0, maç bitti (bugün)"
    assert say(derby, NOW, TR) == "Galatasaray - Fenerbahçe maçı yarın saat 21:30'da"
    assert say(derby, NOW, TR, with_day=False) == "Galatasaray - Fenerbahçe maçı saat 21:30'da"
    assert say(basaksehir, NOW, EN) == "Başakşehir 1, Beşiktaş 1, minute 67"
    assert say(goztepe, NOW, EN) == "Göztepe 2, Çorum FK 0, half-time"
    assert say(derby, NOW, EN) == "Galatasaray v Fenerbahçe, tomorrow at 21:30"
    assert say(konya, NOW + timedelta(days=3), EN) == "Konyaspor 2, Gençlerbirliği 0, full time (Sunday 25 October)"


def test_a_postponed_match():
    postponed = Match("7", datetime(2026, 10, 25, 16, 0, tzinfo=UTC), "Sivasspor", "Hatayspor", None, None,
                      State.SCHEDULED, status="STATUS_POSTPONED")  # fmt: skip
    assert football_report.describe(postponed, NOW, TR) == "Sivasspor - Hatayspor (bugün): ertelendi"


TABLE = {"children": [{"standings": {"entries": [
    {"team": {"displayName": name}, "stats": [{"name": "rank", "value": rank}, {"name": "points", "value": points},
                                              {"name": "gamesPlayed", "value": played}]}
    for name, rank, points, played in [("Galatasaray", 2, 19, 8), ("Amed SFK", 1, 20, 9), ("Fenerbahce", 3, 16, 8),
                                       ("Trabzonspor", 4, 16, 8), ("Kasimpasa", 5, 16, 9), ("Goztepe", 6, 15, 9),
                                       ("Konyaspor", 7, 12, 9)]
] + [{"team": {"displayName": "Broken"}, "stats": []}]}}]}  # fmt: skip


def test_the_table():
    standings = football_report.parse_table(TABLE)
    assert [s.team for s in standings][:2] == ["Amedspor", "Galatasaray"]
    assert football_report.table(standings, TR) == (
        "Süper Lig puan durumu: 1. Amedspor 20 puan, 2. Galatasaray 19 puan, 3. Fenerbahçe 16 puan, "
        "4. Trabzonspor 16 puan, 5. Kasımpaşa 16 puan."
    )
    assert football_report.table(standings, TR, "Konyaspor") == (
        "Konyaspor 9 maçta 12 puanla 7. sırada. Lider Amedspor, 20 puan."
    )
    assert football_report.table(standings, EN, "Amedspor") == "Amedspor is 1st with 20 points from 9 games."
    assert football_report.table(standings, EN, "Galatasaray").endswith("Amedspor leads with 20.")


def test_an_empty_table_is_an_error():
    with pytest.raises(ValueError):
        football_report.parse_table({"children": []})
