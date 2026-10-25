import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.routines.routine_request import Removal, RoutineRequest, asks_for_list, parse, removal
from bilge.core.routines.routine_schedule import EVERY_DAY, WEEKDAYS, WEEKEND

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH


@pytest.mark.parametrize(
    ("said", "expected"),
    [
        ("her gece 21'de hava durumunu söyle", RoutineRequest(EVERY_DAY, 21, 0, "hava durumunu söyle")),
        ("her sabah 8'de günün özetini oku", RoutineRequest(EVERY_DAY, 8, 0, "günün özetini oku")),
        ("hafta içi her gün 7'de haberleri oku", RoutineRequest(WEEKDAYS, 7, 0, "haberleri oku")),
        ("her akşam yedi buçukta salonun ışığını aç", RoutineRequest(EVERY_DAY, 19, 30, "salonun ışığını aç")),
        ("her gece on birde ışıkları kapat", RoutineRequest(EVERY_DAY, 23, 0, "ışıkları kapat")),
        ("hava durumunu her gece 21de söyle", RoutineRequest(EVERY_DAY, 21, 0, "hava durumunu söyle")),
        ("hafta sonları saat 10'da hava durumunu söyle", RoutineRequest(WEEKEND, 10, 0, "hava durumunu söyle")),
        ("her pazartesi saat dokuzda haberleri oku", RoutineRequest(frozenset({0}), 9, 0, "haberleri oku")),
        ("pazartesi ve çarşamba günleri sabah 9'da haberleri oku",
         RoutineRequest(frozenset({0, 2}), 9, 0, "haberleri oku")),
        ("cumartesileri 10'da hava durumunu söyle", RoutineRequest(frozenset({5}), 10, 0, "hava durumunu söyle")),
    ],
)  # fmt: skip
def test_turkish_routines_are_read_with_their_days_time_and_command(said, expected):
    assert parse(said, TR) == expected


@pytest.mark.parametrize(
    "said",
    [
        "saat kaç",
        "yarın 7'de alarm kur",
        # One Monday, not every one.
        "pazartesi 9'da haberleri oku",
        "her sabah haberleri oku",
        "her gün 9'da",
        # Talking about the routine itself is left to the model.
        "her gün 9'da haberleri okuyan bir rutin kur",
        "rutinlerim neler",
    ],
)
def test_turkish_requests_that_are_not_a_full_routine_are_left_alone(said):
    assert parse(said, TR) is None


@pytest.mark.parametrize(
    ("said", "expected"),
    [
        ("every night at 9 tell me the weather", RoutineRequest(EVERY_DAY, 21, 0, "tell me the weather")),
        ("every weekday at 7 read the news", RoutineRequest(WEEKDAYS, 7, 0, "read the news")),
        ("read the news every weekday at 7 am", RoutineRequest(WEEKDAYS, 7, 0, "read the news")),
        ("at 8:30 every monday and wednesday, read my calendar",
         RoutineRequest(frozenset({0, 2}), 8, 30, "read my calendar")),
        ("on weekends at 10 tell me the weather", RoutineRequest(WEEKEND, 10, 0, "tell me the weather")),
        ("every morning at 8 read the daily briefing", RoutineRequest(EVERY_DAY, 8, 0, "read the daily briefing")),
    ],
)  # fmt: skip
def test_english_routines(said, expected):
    assert parse(said, EN) == expected


@pytest.mark.parametrize("said", ["on monday at 9 read the news", "set a timer for 10 minutes", "what time is it"])
def test_english_requests_that_are_not_routines(said):
    assert parse(said, EN) is None


def test_asking_for_the_routines():
    assert asks_for_list("rutinlerim neler", TR)
    assert asks_for_list("rutinlerim", TR)
    assert asks_for_list("hangi rutinler var", TR)
    assert not asks_for_list("akşam rutinini sil", TR)
    assert not asks_for_list("haberleri oku", TR)
    assert asks_for_list("what are my routines", EN)
    assert not asks_for_list("delete the evening routine", EN)


def test_deleting_a_routine_by_name_or_all_of_them():
    assert removal("akşam rutinini sil", TR) == Removal("aksam")
    assert removal("hava durumu rutinini kaldır", TR) == Removal("hava durumu")
    assert removal("bütün rutinleri sil", TR) == Removal("", every=True)
    assert removal("rutinleri sil", TR) == Removal("", every=True)
    assert removal("rutinlerim neler", TR) is None
    assert removal("delete the evening routine", EN) == Removal("evening")
    assert removal("remove all routines", EN) == Removal("", every=True)
