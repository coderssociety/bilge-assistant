from datetime import UTC, datetime, timedelta

import pytest

from bilge.core.alerts import earthquake_alert
from bilge.core.alerts.earthquake_alert import Announced, EarthquakeAlerts, retry_delay
from bilge.core.web import provinces
from bilge.core.web.earthquake_feed import Earthquake

NOW = datetime(2026, 10, 25, 16, 0, tzinfo=UTC)
ISTANBUL = provinces.named("İstanbul")


def quake(id, minutes_ago, magnitude=4.5, lat=40.8, lon=29.0):
    """By default about 25 km from İstanbul."""
    return Earthquake(id, NOW - timedelta(minutes=minutes_ago), lat, lon, 8.0, magnitude, "Marmara Denizi")


def test_a_strong_nearby_earthquake_is_due_once():
    alerts = EarthquakeAlerts(ISTANBUL)
    first = quake("afad:1", 2)
    assert alerts.due([first], NOW) == [first]
    assert alerts.due([first], NOW + timedelta(minutes=2)) == []


@pytest.mark.parametrize(
    "ignored",
    [
        quake("weak", 2, magnitude=3.9),
        # Sındırgı is about 200 km from İstanbul.
        quake("far", 2, lat=39.23, lon=28.08),
    ],
)
def test_weak_or_far_ones_are_not_said(ignored):
    assert EarthquakeAlerts(ISTANBUL).due([ignored], NOW) == []


def test_the_threshold_itself_counts():
    assert len(EarthquakeAlerts(ISTANBUL).due([quake("edge", 2, magnitude=4.0)], NOW)) == 1


def test_at_startup_only_the_last_fifteen_minutes_count_and_older_ones_never_come_up():
    alerts = EarthquakeAlerts(ISTANBUL)
    old, fresh = quake("old", 20), quake("fresh", 10)
    assert alerts.due([old, fresh], NOW) == [fresh]
    # Later polls look back an hour, but the one ignored at startup stays ignored.
    assert alerts.due([old, fresh], NOW + timedelta(minutes=2)) == []


def test_after_startup_a_late_published_one_is_said_within_the_hour():
    alerts = EarthquakeAlerts(ISTANBUL)
    alerts.due([], NOW)
    late, stale = quake("late", 40), quake("stale", 70)
    assert alerts.due([late, stale], NOW) == [late]


def test_the_same_earthquake_from_the_other_source_is_not_said_again():
    alerts = EarthquakeAlerts(ISTANBUL)
    afad = quake("afad:9", 3)
    kandilli = Earthquake("kandilli:x", afad.time + timedelta(seconds=20), 40.81, 29.02, 7.0, 4.7, "MARMARA")
    assert alerts.due([afad], NOW) == [afad]
    assert alerts.due([kandilli], NOW + timedelta(minutes=2)) == []


def test_what_was_said_is_shared_across_watchers():
    announced = Announced()
    first = quake("afad:5", 5)
    assert EarthquakeAlerts(ISTANBUL, announced).due([first], NOW) == [first]
    assert EarthquakeAlerts(ISTANBUL, announced).due([first], NOW + timedelta(minutes=1)) == []


def test_several_new_ones_come_oldest_first():
    alerts = EarthquakeAlerts(ISTANBUL)
    newer, older = quake("b", 1), quake("a", 6)
    assert alerts.due([newer, older], NOW) == [older, newer]


def test_the_retry_delay_doubles_and_stops_at_half_an_hour():
    assert retry_delay(0) == earthquake_alert.POLL_SECONDS == 120
    assert [retry_delay(n) for n in (1, 2, 3, 4)] == [240, 480, 960, 1800]
    assert retry_delay(10) == earthquake_alert.MAX_RETRY_SECONDS
