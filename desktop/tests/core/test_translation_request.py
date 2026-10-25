import pytest

from bilge.core.translation_request import target


@pytest.mark.parametrize(
    ("command", "code"),
    [
        ("İngilizce maili Türkçe oku", "tr"),
        ("Türkçe maili Fransızca olarak oku", "fr"),
        ("Bunu Almancaya çevir", "de"),
        ("haberleri İngilizce oku", "en"),
        ("mailin Türkçesini oku", "tr"),
        ("Fransızca de", "fr"),
        ("ispanyolca diline çevirerek anlat", "es"),
        ("Read my email in Turkish", "tr"),
        ("translate the news into German", "de"),
    ],
)
def test_finds_the_language_to_read_in_not_the_one_the_text_is_in(command: str, code: str) -> None:
    found = target(command)
    assert found is not None and found.code == code


@pytest.mark.parametrize(
    "command", ["Maillerimi oku", "İngilizce maili aç", "Türkçe haberler", "fincanı yıka", "I speak English"]
)
def test_a_request_that_only_mentions_a_language_has_no_target(command: str) -> None:
    assert target(command) is None
