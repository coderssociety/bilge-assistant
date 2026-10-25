import pytest

from bilge.core.interpreter.interpreter_command import is_start, is_stop, language_pair
from bilge.core.language import AssistantLanguage


@pytest.mark.parametrize(
    "command",
    [
        "tercüman modunu aç: Türkçe ve İngilizce",
        "tercüman modunu aç",
        "Almanca tercüme et",
        "bana Fransızca tercüme et",
        "Türkçeden Almancaya tercümanlık yap",
        "tercüman modu",
        "start interpreter mode: English and Turkish",
        "interpret German",
        "be my interpreter",
    ],
)
def test_starts_interpreter_mode(command):
    assert is_start(command)


@pytest.mark.parametrize(
    "command",
    [
        "tercümanı kapat",
        "Bunu Almancaya tercüme et",
        "bu maili Almanca tercüme et",
        "tercüme nedir",
        "stop interpreting",
        "saat kaç",
        "interpreter off",
    ],
)
def test_other_requests_do_not_start_it(command):
    assert not is_start(command)


@pytest.mark.parametrize(
    "said",
    ["tercümanı kapat", "tercüman modunu kapat", "tercümeyi bitir", "stop interpreting", "turn off the interpreter",
     "interpreter off", "Tercümanı durdur."],
)  # fmt: skip
def test_stop_phrases_in_either_language_end_it(said):
    assert is_stop(said)


@pytest.mark.parametrize(
    "said",
    [
        "kapıyı kapat",
        "toplantıyı bitirelim",
        "tercümanı kapatmayı unutma sonra yine konuşuruz tamam mı",
        "stop the car",
        "",
    ],
)
def test_other_speech_is_translated_not_taken_as_the_stop_phrase(said):
    assert not is_stop(said)


@pytest.mark.parametrize(
    ("command", "language", "codes"),
    [
        ("tercüman modunu aç: Türkçe ve İngilizce", AssistantLanguage.TURKISH, ("tr", "en")),
        ("İngilizce ve Almanca tercüman ol", AssistantLanguage.TURKISH, ("en", "de")),
        ("Almanca tercüme et", AssistantLanguage.TURKISH, ("tr", "de")),
        ("interpret German", AssistantLanguage.ENGLISH, ("en", "de")),
        ("tercüman modunu aç", AssistantLanguage.TURKISH, ("tr", "en")),
        ("start the interpreter", AssistantLanguage.ENGLISH, ("en", "tr")),
        ("Türkçe tercüme et", AssistantLanguage.TURKISH, ("tr", "en")),
    ],
)
def test_the_two_languages_default_to_the_assistants_own_and_the_named_one(command, language, codes):
    assert language_pair(command, language).codes == codes
