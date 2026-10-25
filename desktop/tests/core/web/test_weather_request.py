import pytest

from bilge.core.web.weather_request import PartOfDay, asks_about_rain, part_of_day


@pytest.mark.parametrize(
    ("command", "english", "part"),
    [
        ("akşam yağmur var mı", False, PartOfDay.EVENING),
        ("yarın sabah hava nasıl", False, PartOfDay.MORNING),
        ("bugün öğleden sonra", False, PartOfDay.AFTERNOON),
        ("öğlen sıcak mı", False, PartOfDay.NOON),
        ("bu gece kar yağacak mı", False, PartOfDay.NIGHT),
        ("geçen hafta hava nasıldı", False, None),
        ("will it rain tonight", True, PartOfDay.NIGHT),
        ("tomorrow afternoon", True, PartOfDay.AFTERNOON),
        ("how's the weather", True, None),
    ],
)
def test_reads_the_part_of_the_day(command, english, part):
    assert part_of_day(command, english) is part


@pytest.mark.parametrize(
    ("command", "english", "rain"),
    [
        ("yağmur yağacak mı", False, True),
        ("şemsiye alayım mı", False, True),
        ("yağış var mı", False, True),
        ("hava nasıl", False, False),
        ("do I need an umbrella", True, True),
        ("will it rain", True, True),
        ("how warm is it", True, False),
    ],
)
def test_knows_a_question_about_rain(command, english, rain):
    assert asks_about_rain(command, english) is rain
