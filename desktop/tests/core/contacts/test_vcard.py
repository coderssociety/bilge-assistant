from bilge.core.contacts.contact import Contact
from bilge.core.contacts.vcard import parse

CARDS = (
    "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Ahmet Yılmaz\r\nN:Yılmaz;Ahmet;;;\r\n"
    'item1.TEL;TYPE=CELL:0532 123 45 67\r\nTEL;TYPE="work,voice":+90 212 555 00 00\r\n'
    "EMAIL;TYPE=INTERNET:ahmet@example.org\r\nNICKNAME:Memo,Ahmo\r\nEND:VCARD\r\n"
    "BEGIN:VCARD\r\nVERSION:4.0\r\nN:Kaya;Ayşe;;;\r\nTEL;VALUE=uri:tel:+905551112233\r\n"
    "EMAIL:ay\r\n se@example.org\r\nEND:VCARD\r\n"
)


def test_names_numbers_addresses_and_nicknames_are_read():
    assert parse(CARDS) == [
        Contact("Ahmet Yılmaz", ("0532 123 45 67", "+90 212 555 00 00"), ("ahmet@example.org",), ("Memo", "Ahmo")),
        Contact("Ayşe Kaya", ("+905551112233",), ("ayse@example.org",)),
    ]


def test_escaped_text_and_a_company_without_a_person():
    cards = "BEGIN:VCARD\nFN:Ali\\, Veli\nEND:VCARD\nBEGIN:VCARD\nORG:Bilge A.Ş.;Destek\nTEL:444 0 444\nEND:VCARD\n"
    assert [c.name for c in parse(cards)] == ["Ali, Veli", "Bilge A.Ş."]


def test_cards_without_a_name_and_text_outside_cards_are_skipped():
    assert parse("FN:Dışarıda\nBEGIN:VCARD\nTEL:123\nEND:VCARD\nBEGIN:VCARD\nFN:Yarım") == []
