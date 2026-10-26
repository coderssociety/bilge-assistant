"""CardDAV against a real Radicale server on this computer, and what the client refuses to do."""

import threading
from wsgiref.simple_server import WSGIRequestHandler, make_server

import httpx
import pytest

from bilge import contacts
from bilge.core.contacts.contact import Contact

_ADDRESS_BOOK = (
    '<?xml version="1.0" encoding="utf-8"?><mkcol xmlns="DAV:" xmlns:CR="urn:ietf:params:xml:ns:carddav"><set><prop>'
    "<resourcetype><collection/><CR:addressbook/></resourcetype><displayname>Kişiler</displayname></prop></set></mkcol>"
)
_CARD = (
    "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:{uid}\r\nFN:{name}\r\nTEL;TYPE=CELL:{phone}\r\nEMAIL:{email}\r\nEND:VCARD\r\n"
)


class _Quiet(WSGIRequestHandler):
    def log_message(self, *args):
        pass


def _radicale(folder):
    import radicale
    import radicale.config

    configuration = radicale.config.load()
    configuration.update(
        {"auth": {"type": "none"}, "storage": {"filesystem_folder": str(folder)}, "rights": {"type": "owner_only"}},
        "test",
    )
    server = make_server("127.0.0.1", 0, radicale.Application(configuration), handler_class=_Quiet)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


@pytest.fixture(scope="module")
def carddav_url(tmp_path_factory):
    server = _radicale(tmp_path_factory.mktemp("dav"))
    url = f"http://127.0.0.1:{server.server_port}/"
    with httpx.Client(auth=("ayse", "x")) as client:
        client.request("PROPFIND", url + "ayse/", headers={"Depth": "0"})
        assert client.request("MKCOL", url + "ayse/kisiler/", content=_ADDRESS_BOOK).status_code == 201
        for uid, name, phone, email in (("1", "Ahmet Yılmaz", "0532 123 45 67", "ahmet@example.org"),
                                        ("2", "Ayşe Kaya", "+90 555 111 22 33", "ayse@example.org")):  # fmt: skip
            card = _CARD.format(uid=uid, name=name, phone=phone, email=email)
            response = client.put(f"{url}ayse/kisiler/{uid}.vcf", content=card, headers={"Content-Type": "text/vcard"})
            assert response.status_code == 201
    yield url
    server.shutdown()


def test_the_address_book_is_found_from_the_calendar_address(carddav_url):
    found = contacts.CardDAVContacts(carddav_url, "ayse", "x").contacts()
    assert sorted(found, key=lambda c: c.name) == [
        Contact("Ahmet Yılmaz", ("0532 123 45 67",), ("ahmet@example.org",)),
        Contact("Ayşe Kaya", ("+90 555 111 22 33",), ("ayse@example.org",)),
    ]


def test_the_address_of_the_address_book_itself_works_too(carddav_url):
    found = contacts.CardDAVContacts(carddav_url + "ayse/kisiler/", "ayse", "x").contacts()
    assert {c.name for c in found} == {"Ahmet Yılmaz", "Ayşe Kaya"}


def test_an_account_without_an_address_book_says_so(carddav_url):
    with pytest.raises(contacts.ContactsError) as raised:
        contacts.CardDAVContacts(carddav_url, "mehmet", "x").contacts()
    assert raised.value.reason == "no_address_book"


def test_a_password_never_goes_over_plain_http_to_another_computer():
    with pytest.raises(contacts.ContactsError, match="https"):
        contacts.CardDAVContacts("http://dav.example.org/", "ayse", "x").contacts()


def _multistatus(*responses: str) -> bytes:
    return ('<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:carddav">'
            + "".join(responses) + "</d:multistatus>").encode()  # fmt: skip


def _response(href: str, prop: str) -> str:
    return f"<d:response><d:href>{href}</d:href><d:propstat><d:prop>{prop}</d:prop>" \
           "<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>"  # fmt: skip


def test_a_home_on_another_server_is_not_followed_with_the_password():
    asked = []

    def answer(request: httpx.Request) -> httpx.Response:
        asked.append((request.method, str(request.url)))
        home = "<c:addressbook-home-set><d:href>https://evil.example.com/books/</d:href></c:addressbook-home-set>"
        return httpx.Response(207, content=_multistatus(_response("/dav/", home)))

    client = httpx.Client(transport=httpx.MockTransport(answer))
    with pytest.raises(contacts.ContactsError) as raised:
        contacts.CardDAVContacts("https://dav.example.org/dav/", "ayse", "x", client).contacts()
    assert raised.value.reason == "no_address_book"
    assert asked == [("PROPFIND", "https://dav.example.org/dav/")]


def test_a_refused_password_is_a_login_error():
    client = httpx.Client(transport=httpx.MockTransport(lambda request: httpx.Response(401)))
    with pytest.raises(contacts.ContactsError) as raised:
        contacts.CardDAVContacts("https://dav.example.org/", "ayse", "yanlış", client).contacts()
    assert raised.value.reason == "login"


def test_an_answer_that_is_not_xml_is_a_failure():
    client = httpx.Client(transport=httpx.MockTransport(lambda request: httpx.Response(207, content=b"<html")))
    with pytest.raises(contacts.ContactsError) as raised:
        contacts.CardDAVContacts("https://dav.example.org/", "ayse", "x", client).contacts()
    assert raised.value.reason == "failed"
