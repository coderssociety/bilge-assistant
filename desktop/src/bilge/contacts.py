"""Where the address book comes from: Outlook's contacts on Windows (desktop/windows/office.py), or the address book
of the CalDAV account on servers that also speak CardDAV (Nextcloud, Radicale, Baïkal…)."""

import logging
from collections.abc import Iterator
from dataclasses import dataclass
from typing import Protocol
from urllib.parse import urljoin, urlsplit
from xml.etree import ElementTree

import httpx

from bilge.calendars import TIMEOUT_SECONDS, is_secure_address
from bilge.core.contacts import vcard
from bilge.core.contacts.contact import Contact

log = logging.getLogger(__name__)

# A whole address book is fetched for each lookup; more than this is not a personal one.
MAX_RESPONSE_BYTES = 10_000_000
MAX_ADDRESS_BOOKS = 10
_DAV, _CARD = "{DAV:}", "{urn:ietf:params:xml:ns:carddav}"
_DISCOVERY = (
    '<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:carddav">'
    "<d:prop><d:current-user-principal/><c:addressbook-home-set/><d:resourcetype/></d:prop></d:propfind>"
)
_EVERY_CARD = (
    '<?xml version="1.0" encoding="utf-8"?><c:addressbook-query xmlns:d="DAV:" '
    'xmlns:c="urn:ietf:params:xml:ns:carddav"><d:prop><c:address-data/></d:prop><c:filter/></c:addressbook-query>'
)


class ContactsError(Exception):
    """`reason`: "no_address_book", "login", "not_running", "new_outlook" or "failed"."""

    def __init__(self, reason: str, detail: str = ""):
        super().__init__(f"{reason}: {detail}" if detail else reason)
        self.reason = reason


class ContactSource(Protocol):
    def contacts(self) -> list[Contact]: ...


@dataclass(frozen=True)
class _Resource:
    url: str
    is_address_book: bool
    principal: str | None
    homes: tuple[str, ...]
    card: str


class CardDAVContacts:
    """Reads only. The password is sent only to the configured server's own address (https, or http on this
    computer): addresses the server names elsewhere are not followed."""

    def __init__(self, url: str, username: str, password: str, client: httpx.Client | None = None):
        self.url = url
        self.username = username
        self.password = password
        self._client = client

    def contacts(self) -> list[Contact]:
        if not is_secure_address(self.url):
            raise ContactsError("failed", "A CardDAV address must start with https://")
        client = self._client or httpx.Client(timeout=TIMEOUT_SECONDS, follow_redirects=True)
        auth = httpx.BasicAuth(self.username, self.password) if self.username or self.password else None
        try:
            found: list[Contact] = []
            for book in self._address_books(client, auth)[:MAX_ADDRESS_BOOKS]:
                for resource in self._send(client, auth, "REPORT", book, _EVERY_CARD, "1"):
                    found.extend(vcard.parse(resource.card))
            return found
        except httpx.HTTPError as error:
            raise ContactsError("failed", type(error).__name__) from error
        except ElementTree.ParseError as error:
            raise ContactsError("failed", "The server's answer is not XML") from error
        finally:
            if self._client is None:
                client.close()

    def _address_books(self, client: httpx.Client, auth: httpx.Auth | None) -> list[str]:
        here = self._send(client, auth, "PROPFIND", self.url, _DISCOVERY, "0")
        if any(r.is_address_book for r in here):
            return [self.url]
        homes = [home for r in here for home in r.homes]
        principal = next((r.principal for r in here if r.principal), None)
        if not homes and principal:
            homes = [home for r in self._send(client, auth, "PROPFIND", principal, _DISCOVERY, "0") for home in r.homes]
        books = [r.url for home in homes for r in self._send(client, auth, "PROPFIND", home, _DISCOVERY, "1")
                 if r.is_address_book]  # fmt: skip
        if not books:
            raise ContactsError("no_address_book")
        return books

    def _own(self, url: str) -> bool:
        """The configured server itself: same scheme, host and port."""
        mine, other = urlsplit(self.url), urlsplit(url)
        return (mine.scheme, mine.hostname, mine.port) == (other.scheme, other.hostname, other.port)

    def _send(
        self, client: httpx.Client, auth: httpx.Auth | None, method: str, url: str, body: str, depth: str
    ) -> list[_Resource]:
        if not self._own(url):
            log.info("Not following an address book address on another server: %s", url)
            return []
        headers = {"Depth": depth, "Content-Type": "application/xml; charset=utf-8"}
        with client.stream(method, url, content=body.encode(), headers=headers, auth=auth) as response:
            # A redirect must not carry the password over to plain HTTP.
            if not is_secure_address(str(response.url)):
                raise ContactsError("failed", "The address book left HTTPS")
            if response.status_code in (401, 403):
                raise ContactsError("login")
            if response.status_code in (404, 405, 501):
                return []
            if response.status_code != 207:
                raise ContactsError("failed", f"{method} answered {response.status_code}")
            data = bytearray()
            for chunk in response.iter_bytes():
                data.extend(chunk)
                if len(data) > MAX_RESPONSE_BYTES:
                    raise ContactsError("failed", "The address book is too large")
            base = str(response.url)
        return list(_resources(ElementTree.fromstring(bytes(data)), base))


def _resources(root: ElementTree.Element, base: str) -> Iterator[_Resource]:
    for response in root.iter(f"{_DAV}response"):
        href = response.findtext(f"{_DAV}href", "").strip()
        if not href:
            continue
        for propstat in response.iter(f"{_DAV}propstat"):
            if " 200 " not in f"{propstat.findtext(f'{_DAV}status', '')} ":
                continue
            prop = propstat.find(f"{_DAV}prop")
            if prop is None:
                continue
            kind = prop.find(f"{_DAV}resourcetype")
            principal = prop.findtext(f"{_DAV}current-user-principal/{_DAV}href", "").strip()
            homes = tuple(urljoin(base, h.text.strip()) for h in prop.iterfind(f"{_CARD}addressbook-home-set/{_DAV}href")
                          if h.text and h.text.strip())  # fmt: skip
            yield _Resource(
                urljoin(base, href),
                kind is not None and kind.find(f"{_CARD}addressbook") is not None,
                urljoin(base, principal) if principal else None,
                homes,
                prop.findtext(f"{_CARD}address-data", ""),
            )
