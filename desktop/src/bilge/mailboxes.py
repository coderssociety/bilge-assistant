"""The user's inbox, read only: Outlook on Windows (desktop/windows/office.py) or an IMAP account elsewhere. Nothing
here marks a message read or changes the mailbox."""

import email
import imaplib
import logging
import re
import ssl
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from email import policy
from email.message import EmailMessage
from typing import Protocol

from bilge.core.text import folded
from bilge.core.web import html_text

log = logging.getLogger(__name__)

IMAPS_PORT = 993
TIMEOUT_SECONDS = 15
# Only this much of a message is fetched: enough for its text, not for attachments.
MAX_MESSAGE_BYTES = 200_000
# A sender is looked for among this many of the newest messages.
MAX_SCANNED = 200
_HEADERS = "(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])"
_UID = re.compile(rb"\bUID (\d+)")


class MailError(Exception):
    """`reason`: "login", "failed", or Outlook's own ("not_running", "new_outlook", "outlook_failed")."""

    def __init__(self, reason: str, detail: str = ""):
        super().__init__(f"{reason}: {detail}" if detail else reason)
        self.reason = reason


@dataclass(frozen=True)
class MailMessage:
    sender: str
    address: str
    subject: str
    received: datetime | None
    # Empty when only the list was asked for.
    body: str = ""
    # Where the mailbox finds the message again (Outlook's EntryID, an IMAP UID).
    reference: str = ""


class Mailbox(Protocol):
    def unread(self, listed: int, with_bodies: int) -> tuple[int, list[MailMessage]]:
        """How many unread messages there are, and the newest `listed` of them, newest first; the first
        `with_bodies` with their text."""
        ...

    def message(self, sender: str, position: int) -> tuple[int, MailMessage | None]:
        """The `position`th newest message (1 = newest), read or not, from `sender` when one is given, with its text;
        and how many there were to choose from."""
        ...


def sender_matches(name: str, sender: str, address: str) -> bool:
    return folded(name) in folded(f"{sender} {address}")


class IMAPMailbox:
    """An IMAP account over TLS, opened read-only for each request."""

    def __init__(
        self,
        server: str,
        username: str,
        password: str,
        connect: Callable[[str, int], imaplib.IMAP4] | None = None,
    ):
        self.host, self.port = split_server(server)
        self.username = username
        self.password = password
        self._connect = connect or _connect_tls

    def _session[T](self, action: Callable[[imaplib.IMAP4], T]) -> T:
        try:
            imap = self._connect(self.host, self.port)
        except (OSError, imaplib.IMAP4.error) as error:
            raise MailError("failed", f"{type(error).__name__}: {error}") from error
        try:
            try:
                imap.login(self.username, self.password)
            except imaplib.IMAP4.error as error:
                raise MailError("login", str(error)) from error
            status, _ = imap.select("INBOX", readonly=True)
            if status != "OK":
                raise MailError("failed", "INBOX could not be opened")
            return action(imap)
        except (OSError, imaplib.IMAP4.error, ValueError) as error:
            raise MailError("failed", f"{type(error).__name__}: {error}") from error
        finally:
            try:
                imap.logout()
            except (OSError, imaplib.IMAP4.error):
                log.info("IMAP logout failed", exc_info=True)

    def unread(self, listed: int, with_bodies: int) -> tuple[int, list[MailMessage]]:
        def read(imap: imaplib.IMAP4) -> tuple[int, list[MailMessage]]:
            uids = _search(imap, "UNSEEN")
            newest = list(reversed(uids[-listed:])) if listed else []
            headers = _fetch(imap, newest, _HEADERS)
            found = [_message(headers.get(uid, b""), uid) for uid in newest]
            for index, uid in enumerate(newest[:with_bodies]):
                found[index] = _with_body(found[index], _full(imap, uid))
            return len(uids), found

        return self._session(read)

    def message(self, sender: str, position: int) -> tuple[int, MailMessage | None]:
        def pick(imap: imaplib.IMAP4) -> tuple[int, MailMessage | None]:
            uids = list(reversed(_search(imap, "ALL")))
            if sender:
                scanned = uids[:MAX_SCANNED]
                senders = _fetch(imap, scanned, "(BODY.PEEK[HEADER.FIELDS (FROM)])")
                uids = [uid for uid in scanned if _from_matches(senders.get(uid, b""), sender)]
            if position > len(uids):
                return len(uids), None
            uid = uids[position - 1]
            raw = _full(imap, uid)
            return len(uids), _with_body(_message(raw, uid), raw)

        return self._session(pick)


def split_server(server: str) -> tuple[str, int]:
    """ "imap.example.org" or "imap.example.org:993"."""
    host, _, port = server.strip().removeprefix("imaps://").rstrip("/").partition(":")
    if not host:
        raise MailError("failed", "no server")
    try:
        return host, int(port) if port else IMAPS_PORT
    except ValueError as error:
        raise MailError("failed", f"bad port {port!r}") from error


def _connect_tls(host: str, port: int) -> imaplib.IMAP4:
    # Certificates are checked: the password is never sent to a server that can't prove who it is.
    return imaplib.IMAP4_SSL(host, port, ssl_context=ssl.create_default_context(), timeout=TIMEOUT_SECONDS)


def _search(imap: imaplib.IMAP4, criterion: str) -> list[bytes]:
    status, data = imap.uid("SEARCH", criterion)
    if status != "OK":
        raise MailError("failed", f"SEARCH {criterion}")
    # UIDs grow with each new message, so the last ones are the newest.
    return sorted((data[0] or b"").split(), key=int) if data else []


def _fetch(imap: imaplib.IMAP4, uids: list[bytes], items: str) -> dict[bytes, bytes]:
    """The fetched literal of each message, by UID."""
    if not uids:
        return {}
    status, data = imap.uid("FETCH", b",".join(uids).decode(), items)
    if status != "OK":
        raise MailError("failed", "FETCH")
    found: dict[bytes, bytes] = {}
    waiting: bytes | None = None
    for item in data:
        if isinstance(item, tuple):
            uid = _UID.search(item[0])
            if uid is not None:
                found[uid.group(1)] = item[1]
                waiting = None
            else:
                # Some servers name the UID after the literal.
                waiting = item[1]
        elif isinstance(item, bytes) and waiting is not None:
            uid = _UID.search(item)
            if uid is not None:
                found[uid.group(1)] = waiting
            waiting = None
    return found


def _full(imap: imaplib.IMAP4, uid: bytes) -> bytes:
    return _fetch(imap, [uid], f"(BODY.PEEK[]<0.{MAX_MESSAGE_BYTES}>)").get(uid, b"")


def _parsed(raw: bytes) -> EmailMessage:
    return email.message_from_bytes(raw, policy=policy.default)  # type: ignore[return-value]


def _sender(message: EmailMessage) -> tuple[str, str]:
    try:
        addresses = message["from"].addresses if message["from"] is not None else ()
    except (AttributeError, IndexError, ValueError):
        return str(message.get("from", "") or ""), ""
    if not addresses:
        return "", ""
    return addresses[0].display_name or addresses[0].addr_spec, addresses[0].addr_spec


def _message(raw: bytes, uid: bytes) -> MailMessage:
    message = _parsed(raw)
    sender, address = _sender(message)
    try:
        received = message["date"].datetime if message["date"] is not None else None
    except (AttributeError, ValueError):
        received = None
    return MailMessage(sender, address, str(message.get("subject", "") or "").strip(), received, "", uid.decode())


def _from_matches(raw: bytes, name: str) -> bool:
    sender, address = _sender(_parsed(raw))
    return sender_matches(name, sender, address)


def _with_body(found: MailMessage, raw: bytes) -> MailMessage:
    return MailMessage(found.sender, found.address, found.subject, found.received, body_text(raw), found.reference)


def body_text(raw: bytes) -> str:
    """The readable text of a message: its plain part, or its HTML part without markup."""
    message = _parsed(raw)
    part = message.get_body(preferencelist=("plain", "html"))
    if part is None:
        return ""
    try:
        content = part.get_content()
    except (LookupError, ValueError, AssertionError):
        payload = part.get_payload(decode=True) or b""
        content = payload.decode("utf-8", errors="replace") if isinstance(payload, bytes) else str(payload)
    if part.get_content_subtype() == "html":
        content = html_text.extract(content)
    return content.strip()
