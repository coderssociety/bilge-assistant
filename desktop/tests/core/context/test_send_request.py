import pytest

from bilge.core.context import send_request
from bilge.core.context.send_request import SendRequest
from bilge.core.language import AssistantLanguage

EN = AssistantLanguage.ENGLISH


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("bunu Ahmet'e gönder", SendRequest("Ahmet", "bunu")),
        ("Bunu Ahmet'e mail at", SendRequest("Ahmet", "Bunu")),
        ("Şunu Ayşe Kaya'ya ilet", SendRequest("Ayşe Kaya", "Şunu")),
        ("seçili metni Ahmet Yılmaz'a e-posta olarak gönder", SendRequest("Ahmet Yılmaz", "seçili metni")),
        ("şunu ahmet@ornek.com adresine gönder", SendRequest("ahmet@ornek.com", "şunu")),
        ("bu dosyayı Ayşe'ye yolla", SendRequest("Ayşe", "bu dosyayı")),
    ],
)
def test_turkish_requests_to_send_what_is_pointed_at(command, expected):
    assert send_request.parse(command) == expected


@pytest.mark.parametrize(
    "command",
    [
        "bunu gönder",  # whom to is asked by the model
        "Ahmet'e mail at",
        "bunu Ahmet'e mesaj at",  # another channel
        "Ahmet'e 'bunu yarın hallederim' diye mail at",  # dictated words
        "Ahmet'e şunu yaz: bunu gönderdim",
        "bu akşam Ahmet'e gönder",
        "bunu özetle",
    ],
)
def test_other_turkish_commands_are_not_taken(command):
    assert send_request.parse(command) is None


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("send this to Anna", SendRequest("Anna", "this")),
        ("Email this to anna@example.org.", SendRequest("anna@example.org", "this")),
        ("forward the selected text to Bob please", SendRequest("Bob", "the selected text")),
        ("send this file to Anna by email", SendRequest("Anna", "this file")),
    ],
)
def test_english_requests_to_send_what_is_pointed_at(command, expected):
    assert send_request.parse(command, EN) == expected


@pytest.mark.parametrize(
    "command", ["send Anna an email", "send this evening to Anna", "send this to Anna as a message", "text this to Bob"]
)
def test_other_english_commands_are_not_taken(command):
    assert send_request.parse(command, EN) is None
