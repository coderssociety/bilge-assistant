import pytest

from bilge.core.contacts.contact import Contact
from bilge.core.language import AssistantLanguage
from bilge.desktop.base import PairedPhone
from bilge.desktop.process import DesktopError, MissingProgram, NotPossibleHere
from bilge.tools.base import Risk, ToolError
from bilge.tools.builtin.contacts import ContactLookup
from bilge.tools.desktop.messages import send_message_tool

TR = AssistantLanguage.TURKISH
PHONE = PairedPhone("a1b2", "Pixel 7")


class Book:
    def contacts(self):
        return [Contact("Ahmet Yılmaz", ("0532 123 45 67",)), Contact("Ayşe Kaya", (), ("ayse@example.org",))]


class Phone:
    def __init__(self, error=None, send_error=None):
        self.error = error
        self.send_error = send_error
        self.sent = []

    def reachable_phone(self):
        if self.error:
            raise self.error
        return PHONE

    def send(self, phone, number, text):
        if self.send_error:
            raise self.send_error
        self.sent.append((phone, number, text))


def tool(messages):
    return send_message_tool(messages, ContactLookup(lambda: Book(), TR), TR)


def test_the_number_is_found_in_the_contacts_and_read_back_with_the_words_said():
    phone = Phone()
    send = tool(phone)
    arguments = send.refine({"recipient": "Ahmet", "text": "Birazdan oradayım."}, "Ahmet'e mesaj at: geliyorum")
    assert arguments == {"recipient": "Ahmet", "text": "geliyorum"}
    assert send.risk is Risk.CONFIRM
    assert send.question(arguments) == (
        "Ahmet Yılmaz (+905321234567) kişisine Pixel 7 telefonundan şu SMS'i göndereyim mi: geliyorum"
    )
    assert send.run(arguments) == "SMS'i Ahmet Yılmaz kişisine gönderdim."
    assert phone.sent == [(PHONE, "+905321234567", "geliyorum")]


def test_a_spoken_number_needs_no_contact():
    phone = Phone()
    send = tool(phone)
    arguments = {"recipient": "0555 111 22 33", "text": "Geç kalacağım."}
    assert send.question(arguments).startswith("0555 111 22 33 (+905551112233) kişisine")
    send.run(arguments)
    assert phone.sent == [(PHONE, "+905551112233", "Geç kalacağım.")]


def test_nothing_is_sent_that_was_not_asked_about():
    phone = Phone()
    send = tool(phone)
    with pytest.raises(ToolError):
        send.run({"recipient": "Ahmet", "text": "geliyorum"})
    send.question({"recipient": "Ahmet", "text": "geliyorum"})
    with pytest.raises(ToolError):
        send.run({"recipient": "Ahmet", "text": "başka bir şey"})
    assert phone.sent == []


@pytest.mark.parametrize(
    ("messages", "arguments", "said"),
    [
        (None, {"recipient": "Ahmet", "text": "x"}, "Windows'ta SMS gönderemiyorum"),
        (Phone(MissingProgram("kdeconnect-cli")), {"recipient": "Ahmet", "text": "x"}, "kdeconnect-cli yüklü değil"),
        (Phone(NotPossibleHere("none")), {"recipient": "Ahmet", "text": "x"}, "erişilebilen bir telefon yok"),
        (Phone(), {"recipient": "Zeynep", "text": "x"}, "'Zeynep' adında birini bulamadım"),
        (Phone(), {"recipient": "Ayşe", "text": "x"}, "'Ayşe Kaya' için kayıtlı bir telefon numarası bulamadım"),
        (Phone(), {"recipient": "Ahmet", "text": ""}, "ne yazmamı istediğini anlayamadım"),
        (Phone(), {"recipient": "Ahmet", "text": "uzun " * 200}, "çok uzun"),
    ],
)
def test_why_it_cannot_be_sent_is_told_when_sending(messages, arguments, said):
    send = tool(messages)
    assert send.question(arguments) is None
    with pytest.raises(ToolError, match=said):
        send.run(arguments)


def test_a_phone_that_fails_to_send_is_told():
    send = tool(Phone(send_error=DesktopError("unreachable")))
    arguments = {"recipient": "Ahmet", "text": "geliyorum"}
    send.question(arguments)
    with pytest.raises(ToolError, match="SMS gönderilmedi"):
        send.run(arguments)
