import pytest

from bilge.core.mail_request import asks_for_content


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
