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
        ("akşamları 8'de haberleri oku", RoutineRequest(EVERY_DAY, 20, 0, "haberleri oku")),
        ("geceleri 11'de ışıkları kapat", RoutineRequest(EVERY_DAY, 23, 0, "ışıkları kapat")),
        ("sabahları 7'de haberleri oku", RoutineRequest(EVERY_DAY, 7, 0, "haberleri oku")),
        ("her hafta sonu saat 10'da annemi aramayı hatırlat",
         RoutineRequest(WEEKEND, 10, 0, "annemi aramayı hatırlat")),
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
        # Once: next weekend, not every one.
        "hafta sonu saat 10'da annemi aramayı hatırlat",
        "bu hafta sonu 10'da annemi ara",
        "önümüzdeki hafta sonu 10'da annemi ara",
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
        # Bare hours follow the same daytime rule as Turkish.
        ("every day at 3 remind me to drink water", RoutineRequest(EVERY_DAY, 15, 0, "remind me to drink water")),
        ("every day at 3 am check the backups", RoutineRequest(EVERY_DAY, 3, 0, "check the backups")),
        ("every morning at 6 read the news", RoutineRequest(EVERY_DAY, 6, 0, "read the news")),
        ("every night at 12 turn off the lights", RoutineRequest(EVERY_DAY, 0, 0, "turn off the lights")),
        ("every night at 2 turn off the lights", RoutineRequest(EVERY_DAY, 2, 0, "turn off the lights")),
        ("every weekend at 10 tell me the weather", RoutineRequest(WEEKEND, 10, 0, "tell me the weather")),
    ],
)  # fmt: skip
def test_english_routines(said, expected):
    assert parse(said, EN) == expected


@pytest.mark.parametrize(
    "said",
    ["on monday at 9 read the news", "set a timer for 10 minutes", "what time is it",
     "next weekend at 10 remind me to pay rent", "this weekend at 10 call mom", "weekend at 10 call mom"],
)  # fmt: skip
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


@pytest.mark.parametrize(
    ("said", "language"),
    [("stop the morning routine", EN), ("my morning routine is boring, stop the music", EN),
     ("my morning routine is boring, delete that song", EN), ("rutini kapat", TR), ("sabah rutinini kapat", TR),
     ("rutin kontrol randevumu iptal et", TR)],
)  # fmt: skip
def test_only_deleting_the_routine_itself_is_a_removal(said, language):
    assert removal(said, language) is None


def test_routine_as_an_adjective_is_not_the_routine_list():
    assert not asks_for_list("yarın rutin kontrolüm var mı", TR)
    assert asks_for_list("rutin var mı", TR)
