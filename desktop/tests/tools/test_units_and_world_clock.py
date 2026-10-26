from datetime import datetime
from zoneinfo import ZoneInfo

import pytest

from bilge.brain.agent import resolve
from bilge.core.language import AssistantLanguage
from bilge.tools.base import ToolError
from bilge.tools.builtin.units import convert_units
from bilge.tools.builtin.world_clock import world_clock_tool

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
NOW = datetime(2026, 10, 25, 14, 30, tzinfo=ZoneInfo("Europe/Istanbul"))


def answer(tool, command: str, language=TR, arguments=None) -> str:
    refined = tool.refine(arguments or {}, resolve(command, language))
    return tool.run(refined)


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("on mil kaç kilometre", "10 mil yaklaşık 16,09 kilometre eder."),
        ("iki litre kaç bardak", "2 litre 10 su bardağı eder."),
        ("beş feet on inç kaç santim", "5 feet 10 inç 177,8 santimetre eder."),
        ("bir GB kaç MB", "1 gigabayt 1024 megabayt eder."),
        ("yüz fahrenheit kaç derece", "100 Fahrenheit derece yaklaşık 37,78 santigrat derece eder."),
    ],
)
def test_conversions_are_spoken_in_turkish(command, expected):
    assert answer(convert_units(TR), command) == expected


def test_conversions_are_spoken_in_english_with_plurals():
    tool = convert_units(EN)
    assert answer(tool, "how many feet in a mile", EN) == "1 mile is 5280 feet."
    assert answer(tool, "10 miles to km", EN) == "10 miles is about 16.09 kilometers."
    assert answer(tool, "convert 0.5 liters to cups", EN) == "0.5 liters is about 2.11 cups."


def test_what_was_said_wins_over_the_models_numbers():
    tool = convert_units(TR)
    refined = tool.refine({"quantity": "20 mile", "to": "meter"}, "10 mil kaç kilometre")
    assert refined == {"quantity": "10 mile", "to": "kilometer"}


def test_a_model_amount_that_was_never_said_is_dropped():
    tool = convert_units(EN)
    command = "could you tell me how far 26.2 miles is in kilometers please"
    assert tool.refine({"quantity": "26.2 mile", "to": "km"}, command)["quantity"] == "26.2 mile"
    assert tool.refine({"quantity": "42 mile", "to": "km"}, command)["quantity"] == ""
    with pytest.raises(ToolError, match="didn't get"):
        tool.run({"quantity": "", "to": "km"})


def test_units_of_different_kinds_are_refused():
    with pytest.raises(ToolError, match="çevrilemez"):
        convert_units(TR).run({"quantity": "5 meter", "to": "kilogram"})


def test_time_in_another_city():
    tool = world_clock_tool(TR, clock=lambda: NOW)
    assert answer(tool, "Tokyo'da saat kaç") == "Tokyo'da saat 20:30, Pazar."
    assert answer(tool, "Paris'te saat kaç") == "Paris'te saat 12:30, Pazar."
    english = world_clock_tool(EN, clock=lambda: NOW)
    assert answer(english, "what time is it in New York", EN) == "It's 07:30 on Sunday in New York."


def test_time_differences_in_both_directions_and_between_two_places():
    tool = world_clock_tool(TR, clock=lambda: NOW)
    assert answer(tool, "New York ile aramızda kaç saat fark var") == "New York bizden 7 saat geride; orada saat 07:30."
    assert answer(tool, "Hindistan ile saat farkı ne") == "Hindistan bizden 2 saat 30 dakika ileride; orada saat 17:00."
    assert answer(tool, "İstanbul ile saat farkı ne") == "İstanbul ile aramızda saat farkı yok."
    assert answer(tool, "Tokyo ile New York arasında kaç saat fark var") == "Tokyo, New York'tan 13 saat ileride."
    english = world_clock_tool(EN, clock=lambda: NOW)
    assert answer(english, "how many hours ahead is Tokyo", EN) == "Tokyo is 6 hours ahead of you; it's 20:30 there."
    assert answer(english, "time difference with the United States", EN).startswith("The United States is 7 hours")


def test_unknown_places_are_named_back():
    tool = world_clock_tool(TR, clock=lambda: NOW)
    with pytest.raises(ToolError, match="Atlantis"):
        tool.run({"place": "Atlantis"})
    assert tool.run({"place": "America/Phoenix"}).startswith("Phoenix'")
