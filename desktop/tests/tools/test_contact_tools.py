import pytest

from bilge import contacts
from bilge.core.contacts.contact import Contact
from bilge.core.language import AssistantLanguage
from bilge.tools.base import ToolError
from bilge.tools.builtin.contacts import ContactLookup, find_contact_tool

TR = AssistantLanguage.TURKISH
PEOPLE = [
    Contact("Ahmet Yılmaz", ("0532 123 45 67",), ("ahmet@example.org",)),
    Contact("Ayşe Kaya", (), ("ayse@example.org",)),
]


class Book:
    def __init__(self, people=None, error=None):
        self.people = people or []
        self.error = error

    def contacts(self):
        if self.error:
            raise self.error
        return self.people


def tool(source):
    return find_contact_tool(ContactLookup(lambda: source, TR), TR)


def test_the_number_or_the_address_asked_for_is_said():
    find = tool(Book(PEOPLE))
    assert find.run({"name": "Ahmet'in", "detail": "phone"}) == "Ahmet Yılmaz: telefonu 0532 123 45 67."
    assert find.run({"name": "Ayşe", "detail": "email"}) == "Ayşe Kaya: e-postası ayse@example.org."
    assert find.run({"name": "Ayşe"}) == "Ayşe Kaya: kayıtlı telefonu yok, e-postası ayse@example.org."


def test_someone_not_in_the_book_is_named_back():
    with pytest.raises(ToolError, match="'Zeynep' adında birini bulamadım"):
        tool(Book(PEOPLE)).run({"name": "Zeynep"})


@pytest.mark.parametrize(
    ("source", "said"),
    [
        (None, "Kişiler bağlı değil"),
        (Book(error=contacts.ContactsError("no_address_book")), "adres defteri sunmuyor"),
        (Book(error=contacts.ContactsError("login")), "parolayı kabul etmedi"),
        (Book(error=contacts.ContactsError("not_running")), "Outlook açık değil"),
        (Book(error=contacts.ContactsError("failed", "boom")), "Adres defterine ulaşamadım"),
    ],
)
def test_why_the_book_could_not_be_read_is_told(source, said):
    with pytest.raises(ToolError, match=said):
        tool(source).run({"name": "Ahmet"})
