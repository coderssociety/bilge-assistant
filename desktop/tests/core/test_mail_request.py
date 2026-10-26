import pytest

from bilge.brain.agent import resolve
from bilge.core.language import AssistantLanguage
from bilge.core.mail_request import asks_for_content, position, reply_text, sender


@pytest.mark.parametrize(
    ("command", "wants_content"),
    [
        ("Maillerimi oku", True),
        ("E-postalarımı okuyabilir misin", True),
        ("İçeriklerini oku", True),
        ("E-postanın içeriğini oku", True),
        ("Ne yazıyor", True),
        ("Google ne yazmış", True),
        ("özetle", True),
        ("Read my email", True),
        ("What does it say?", True),
        ("Kaç mailim var", False),
        ("Yeni e-posta var mı", False),
        ("Any new mail?", False),
    ],
)
def test_knows_when_the_messages_themselves_are_wanted(command: str, wants_content: bool) -> None:
    assert asks_for_content(command) is wants_content


@pytest.mark.parametrize(
    ("command", "name"),
    [
        ("Ahmet'in mailini oku", "Ahmet"),
        ("Ayşe'nin son e-postasını oku", "Ayşe"),
        ("Mehmet'ten gelen maili oku", "Mehmet"),
        ("Ahmet'in ikinci mailini oku", "Ahmet"),
        ("Read the email from Anna", "Anna"),
        ("Read John's latest email", "John"),
        ("Read the email from yesterday", None),
        ("Son mailimi oku", None),
    ],
)
def test_reads_whose_mail_is_asked_for(command: str, name: str | None) -> None:
    assert sender(resolve(command, AssistantLanguage.TURKISH)) == name


@pytest.mark.parametrize(
    ("command", "expected"),
    [
        ("ikinci maili oku", 2),
        ("üçüncü e-postayı oku", 3),
        ("birinci maili oku", 1),
        ("son mailimi oku", 1),
        ("read the second email", 2),
        ("read my latest email", 1),
        ("maillerimi oku", None),
        ("ikinci şarkıyı çal", None),
    ],
)
def test_reads_which_message_is_asked_for(command: str, expected: int | None) -> None:
    assert position(resolve(command, AssistantLanguage.TURKISH)) == expected


@pytest.mark.parametrize(
    ("command", "words"),
    [
        ("buna yanıt ver: yarın uygunum", "yarın uygunum"),
        ("buna yanıt ver yarın uygunum", "yarın uygunum"),
        ("Ahmet'in mailine teşekkür ederim diye cevap yaz", "teşekkür ederim"),
        ("Ahmet'e toplantıya geleceğim diye yanıt ver", "toplantıya geleceğim"),
        ("yarın saat onda geleceğim diye cevap yaz", "yarın saat 10'da geleceğim"),
        ("cevap olarak tamam yaz lütfen", "tamam"),
        ("reply to it: I'm available tomorrow", "I'm available tomorrow"),
        ("reply to that email saying thanks, see you then", "thanks, see you then"),
        ("reply to Anna's email with thank you please", "thank you"),
        ("answer “sounds good”", "sounds good"),
        ("buna cevap ver", None),
        ("yanıtla", None),
        ("maili oku: yarın", None),
    ],
)
def test_a_reply_is_only_the_words_the_user_dictated(command: str, words: str | None) -> None:
    assert reply_text(resolve(command, AssistantLanguage.TURKISH)) == words
