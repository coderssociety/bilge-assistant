import pytest

from bilge.core.message_request import message_text


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("Ahmet'e mesaj at: geliyorum", "geliyorum"),
        ("Ayşe'ye SMS gönder: Toplantı 10'da, unutma.", "Toplantı 10'da, unutma"),
        ("Ayşe'ye 'geç kalacağım' diye mesaj gönder", "geç kalacağım"),
        ("Ahmet'e geliyorum diye mesaj yaz lütfen", "geliyorum"),
        ("geliyorum diye Ahmet'e mesaj at", "geliyorum"),
        ("text Anna saying I'm on my way", "I'm on my way"),
        ("send a message to Tom: running late", "running late"),
    ],
)
def test_the_dictated_words_are_kept_as_said(command, expected):
    assert message_text(command) == expected


@pytest.mark.parametrize(
    "command",
    ["Ahmet'e yarın geleceğimi mesaj at", "Ahmet'in numarası ne", "mesaj at", "Ahmet'e mesaj at:  "],
)
def test_no_plainly_dictated_words(command):
    assert message_text(command) is None
