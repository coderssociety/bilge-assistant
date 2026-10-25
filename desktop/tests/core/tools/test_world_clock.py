from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from bilge.core.tools import world_clock

ISTANBUL = ZoneInfo("Europe/Istanbul")
# Istanbul keeps +03:00 all year; New York is on summer time (UTC-4) until 1 November.
NOW = datetime(2026, 10, 25, 14, 30, tzinfo=ISTANBUL)


def names(command: str) -> tuple[list[str], bool] | None:
    found = world_clock.parse(command)
    return ([place.english for place in found.places], found.difference) if found else None


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("Tokyo'da saat kaç", (["Tokyo"], False)),
        ("Londra saati kaç", (["London"], False)),
        ("Hindistan'da şu an saat kaç", (["India"], False)),
        ("New York'ta saat kaç oldu", (["New York"], False)),
        ("New York ile aramızda kaç saat fark var", (["New York"], True)),
        ("Tokyo'yla saat farkı ne", (["Tokyo"], True)),
        ("Tokyo ile New York arasında kaç saat fark var", (["Tokyo", "New York"], True)),
        ("what time is it in London", (["London"], False)),
        ("what's the time in Sydney right now", (["Sydney"], False)),
        ("time difference with Germany", (["Germany"], True)),
        ("how many hours ahead is Tokyo", (["Tokyo"], True)),
    ],
)
def test_places_and_questions_are_recognized(command, expected):
    assert names(command) == expected


@pytest.mark.parametrize(
    "command",
    ["saat kaç", "Paris'te hava nasıl", "Ankara'yı aç", "Tokyo ile Paris", "Tokyo ile New York'ta saat kaç", "Tokyo"],
)
def test_other_requests_are_left_alone(command):
    assert world_clock.parse(command) is None


def test_every_zone_in_the_table_exists():
    for place in world_clock.PLACES:
        assert world_clock.time_there(place, NOW).tzinfo is not None


def test_time_and_difference_follow_the_zones():
    tokyo, new_york = world_clock.place_named("Tokyo"), world_clock.place_named("new york")
    assert tokyo is not None and new_york is not None
    assert f"{world_clock.time_there(tokyo, NOW):%H:%M}" == "20:30"
    assert world_clock.difference(tokyo, NOW) == timedelta(hours=6)
    assert world_clock.difference(new_york, NOW) == timedelta(hours=-7)
    assert world_clock.difference(tokyo, NOW, new_york) == timedelta(hours=13)
    india = world_clock.place_named("Hindistan")
    assert india is not None and world_clock.difference(india, NOW) == timedelta(hours=2, minutes=30)


def test_a_zone_the_model_names_is_accepted_but_not_nonsense():
    phoenix = world_clock.place_named("America/Phoenix")
    assert phoenix is not None and phoenix.english == "Phoenix"
    assert world_clock.place_named("Mars/Olympus") is None
    assert world_clock.place_named("Atlantis") is None
