import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.notes.note_request import Addition, addition, asks_for_list

EN = AssistantLanguage.ENGLISH
TR = AssistantLanguage.TURKISH


@pytest.mark.parametrize(
    ("command", "note", "text"),
    [
        ("alışveriş notuma süt ekle", "alışveriş", "süt"),
        ("Toplantı notuna şunu ekle: bütçe onaylandı", "Toplantı", "bütçe onaylandı"),
        ("market notuma 2 ekmek ve süt yazar mısın", "market", "2 ekmek ve süt"),
        ("toplantı notunun sonuna 'bütçe onaylandı' diye ekle", "toplantı", "bütçe onaylandı"),
        ("lütfen tarif notuma bir tutam tuz ekle", "tarif", "bir tutam tuz"),
        ("Proje notlarıma ekle, sunum cuma günü", "Proje", "sunum cuma günü"),
    ],
)
def test_turkish_additions_keep_the_users_own_words(command, note, text):
    assert addition(command) == Addition(note, text)


@pytest.mark.parametrize(
    ("command", "note", "text"),
    [
        ("add milk to my shopping note", "shopping", "milk"),
        ("append the budget is approved to the meeting note", "meeting", "the budget is approved"),
        ("add to my shopping note: eggs and bread", "shopping", "eggs and bread"),
        ("write in my meeting note that the demo moved to Friday", "meeting", "the demo moved to Friday"),
    ],
)
def test_english_additions(command, note, text):
    assert addition(command, EN) == Addition(note, text)


@pytest.mark.parametrize(
    "command",
    [
        "toplantı notu diye not al",
        "süt almayı listeme ekle",
        "notuma süt ekle",
        "alışveriş notumu oku",
        "alışveriş notuma bak",
        "yarın sabah süt almayı hatırlat",
    ],
)
def test_other_requests_are_not_additions(command):
    assert addition(command) is None


@pytest.mark.parametrize(
    ("command", "language", "expected"),
    [
        ("notlarım neler", TR, True),
        ("son notlarım", TR, True),
        ("hangi notlarım var", TR, True),
        ("notlarımı listele", TR, True),
        ("son notumu oku", TR, False),
        ("notlarımı aç", TR, False),
        ("tarif notumu oku", TR, False),
        ("notlarımda süt var mı", TR, False),
        ("list my notes", EN, True),
        ("what notes do I have", EN, True),
        ("show my recent notes", EN, True),
        ("read my recipe note", EN, False),
        ("open my notes", EN, False),
        ("add milk to my notes", EN, False),
    ],
)
def test_asking_for_the_list_of_notes(command, language, expected):
    assert asks_for_list(command, language) is expected
