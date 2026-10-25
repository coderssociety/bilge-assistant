"""HTTP GET for anything the assistant fetches from the internet, limited to the public internet.

The host is resolved once, every address is checked, and the connection goes to a checked address with
the original name used for TLS and the Host header. Checking a name and then letting a library resolve it
again leaves a gap: the name could resolve to a local address the second time (DNS rebinding), and a web page
could then reach the router or a service on this machine.
"""

import http.client
import ipaddress
import json
import socket
import ssl
import time
from dataclasses import dataclass
from enum import StrEnum
from typing import Any
from urllib.parse import urljoin, urlsplit

from bilge.core.language import AssistantLanguage
from bilge.core.web import network_address

TIMEOUT_SECONDS = 15
# For the whole fetch: a server trickling one byte at a time would otherwise keep the assistant waiting.
TOTAL_SECONDS = 25
MAX_BYTES = 3_000_000
MAX_REDIRECTS = 5
TRANSIENT_STATUSES = frozenset({502, 503, 504})
RETRY_DELAY_SECONDS = 0.4
ALLOWED_PORTS = frozenset({80, 443})
_DEFAULT_PORTS = {"http": 80, "https": 443}
USER_AGENT = "Mozilla/5.0 (compatible; Bilge/0.1)"
# For the few services that turn away anything that doesn't look like a browser.
BROWSER_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
)
_CHUNK = 64 * 1024
_IPV4_COMPATIBLE = ipaddress.ip_network("::/96")


class Reason(StrEnum):
    CONNECT = "connect"
    NOT_FOUND = "notFound"
    LOCAL = "local"
    UNSUPPORTED = "unsupported"
    REDIRECTS = "redirects"
    TOO_LARGE = "tooLarge"
    TOO_SLOW = "tooSlow"
    STATUS = "status"
    UNEXPECTED = "unexpected"


class WebFetchError(Exception):
    """A reason code rather than text: anything the server sent (a redirect target, a status line) could be an
    instruction aimed at the model, which reads tool errors. `describe` turns it into a sentence."""

    def __init__(self, reason: Reason, status: int | None = None):
        super().__init__(reason.value if status is None else f"{reason.value} {status}")
        self.reason = reason
        self.status = status


class LocalAddressError(WebFetchError):
    def __init__(self) -> None:
        super().__init__(Reason.LOCAL)


_SENTENCES = {
    AssistantLanguage.TURKISH: {
        Reason.CONNECT: "Sunucuya bağlanamadım.",
        Reason.NOT_FOUND: "Adresi bulamadım; internet bağlantısı çalışıyor mu?",
        Reason.LOCAL: "Yerel ağdaki adresleri açmıyorum.",
        Reason.UNSUPPORTED: "Bu tür bir adresi açamıyorum.",
        Reason.REDIRECTS: "Sayfa beni sürekli başka bir adrese yönlendirdi.",
        Reason.TOO_LARGE: "Sayfa okunamayacak kadar büyük.",
        Reason.TOO_SLOW: "Sayfa çok geç yanıt verdi.",
        Reason.UNEXPECTED: "Sunucudan anlayamadığım bir yanıt geldi.",
        "missing": "Sayfa bulunamadı.",
        "refused": "Site erişime izin vermedi.",
        "busy": "Site şu an çok yoğun, biraz sonra yine deneyebilirim.",
        "server": "Sunucu şu an yanıt veremiyor.",
    },
    AssistantLanguage.ENGLISH: {
        Reason.CONNECT: "I couldn't connect to the server.",
        Reason.NOT_FOUND: "I couldn't find the address; is the internet connection working?",
        Reason.LOCAL: "I don't open addresses on the local network.",
        Reason.UNSUPPORTED: "I can't open that kind of address.",
        Reason.REDIRECTS: "The page kept sending me to another address.",
        Reason.TOO_LARGE: "The page is too large to read.",
        Reason.TOO_SLOW: "The page took too long to answer.",
        Reason.UNEXPECTED: "The server sent an answer I couldn't understand.",
        "missing": "The page wasn't found.",
        "refused": "The site refused access.",
        "busy": "The site is busy right now; I can try again in a little while.",
        "server": "The server can't answer right now.",
    },
}


def describe(error: WebFetchError, language: AssistantLanguage) -> str:
    """A sentence for the user in their language."""
    sentences = _SENTENCES[language]
    if error.reason is not Reason.STATUS:
        return sentences[error.reason]
    status = error.status or 0
    if status in (404, 410):
        return sentences["missing"]
    if status in (401, 403, 451):
        return sentences["refused"]
    return sentences["busy" if status == 429 else "server"]


@dataclass(frozen=True)
class Response:
    url: str
    status: int
    content_type: str
    body: bytes

    def text(self) -> str:
        charset = "utf-8"
        for part in self.content_type.split(";")[1:]:
            key, _, value = part.strip().partition("=")
            if key.lower() == "charset" and value:
                charset = value.strip("\"'")
        try:
            return self.body.decode(charset, errors="replace")
        except LookupError:
            return self.body.decode("utf-8", errors="replace")


def get(
    url: str,
    language: AssistantLanguage = AssistantLanguage.TURKISH,
    max_bytes: int = MAX_BYTES,
    user_agent: str = USER_AGENT,
) -> Response:
    response = _follow(url, language, max_bytes, user_agent)
    if response.status in TRANSIENT_STATUSES:
        # One retry for a gateway hiccup: Open-Meteo answered 503 once and fine right after.
        time.sleep(RETRY_DELAY_SECONDS)
        response = _follow(url, language, max_bytes, user_agent)
    return response


def get_json(url: str, language: AssistantLanguage = AssistantLanguage.TURKISH) -> Any:
    """The decoded body of a 200 answer; anything else is a fetch error."""
    response = get(url, language)
    if response.status != 200:
        raise WebFetchError(Reason.STATUS, response.status)
    try:
        return json.loads(response.body)
    except ValueError as error:
        raise WebFetchError(Reason.UNEXPECTED) from error


def _follow(url: str, language: AssistantLanguage, max_bytes: int, user_agent: str) -> Response:
    deadline = time.monotonic() + TOTAL_SECONDS
    current = url
    for _ in range(MAX_REDIRECTS + 1):
        response, location = _get_once(current, language, max_bytes, deadline, user_agent)
        if location is None:
            return response
        current = urljoin(current, location)
    raise WebFetchError(Reason.REDIRECTS)


def _get_once(
    url: str, language: AssistantLanguage, max_bytes: int, deadline: float, user_agent: str
) -> tuple[Response, str | None]:
    parts = urlsplit(url)
    scheme = parts.scheme.lower()
    if scheme not in _DEFAULT_PORTS or not parts.hostname:
        raise WebFetchError(Reason.UNSUPPORTED)
    try:
        port = parts.port or _DEFAULT_PORTS[scheme]
    except ValueError as error:
        raise WebFetchError(Reason.UNSUPPORTED) from error
    if port not in ALLOWED_PORTS:
        raise WebFetchError(Reason.UNSUPPORTED)
    host = parts.hostname
    if network_address.is_local_name(host):
        raise LocalAddressError()
    path = (parts.path or "/") + (f"?{parts.query}" if parts.query else "")
    headers = {
        "Host": host if port == _DEFAULT_PORTS[scheme] else f"{host}:{port}",
        "User-Agent": user_agent,
        "Accept-Language": "en,tr;q=0.8" if language is AssistantLanguage.ENGLISH else "tr,en;q=0.8",
        "Accept-Encoding": "identity",
    }
    last_error: Exception | None = None
    # Each checked address is tried in turn: a dual-stack name may list IPv6 first on a network without it.
    for address in _public_addresses(host, port):
        connection = _PinnedConnection(scheme, host, port, address)
        try:
            connection.putrequest("GET", path, skip_host=True, skip_accept_encoding=True)
            for name, value in headers.items():
                connection.putheader(name, value)
            connection.endheaders()
            reply = connection.getresponse()
            location = reply.getheader("Location")
            if reply.status in (301, 302, 303, 307, 308) and location:
                return Response(url, reply.status, "", b""), location
            body = _read_limited(reply, max_bytes, deadline)
            return Response(url, reply.status, reply.getheader("Content-Type", ""), body), None
        except (OSError, http.client.HTTPException) as error:
            last_error = error
        finally:
            connection.close()
    raise WebFetchError(Reason.CONNECT) from last_error


def _public_addresses(host: str, port: int) -> list[str]:
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except socket.gaierror as error:
        raise WebFetchError(Reason.NOT_FOUND) from error
    addresses = list(dict.fromkeys(info[4][0].split("%")[0] for info in infos))
    # Every address must be public: a name with one public and one private address could still be steered.
    if not addresses or not all(_is_public(a) for a in addresses):
        raise LocalAddressError()
    return addresses


def _is_public(address: str) -> bool:
    """Both checks must agree; the standard library also unwraps IPv4-mapped and 6to4 forms."""
    try:
        ip = ipaddress.ip_address(address)
    except ValueError:
        return False
    if isinstance(ip, ipaddress.IPv6Address):
        # The deprecated IPv4-compatible form (::127.0.0.1) has no public use.
        if ip in _IPV4_COMPATIBLE:
            return False
        embedded = ip.ipv4_mapped or ip.sixtofour
        if embedded is not None and not embedded.is_global:
            return False
    return ip.is_global and network_address.is_public(address)


def _read_limited(reply: http.client.HTTPResponse, max_bytes: int, deadline: float) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while chunk := reply.read(_CHUNK):
        total += len(chunk)
        if total > max_bytes:
            raise WebFetchError(Reason.TOO_LARGE)
        if time.monotonic() > deadline:
            raise WebFetchError(Reason.TOO_SLOW)
        chunks.append(chunk)
    return b"".join(chunks)


class _PinnedConnection(http.client.HTTPConnection):
    """Connects to an address checked beforehand while keeping the host name for TLS and the Host header."""

    def __init__(self, scheme: str, host: str, port: int, address: str):
        super().__init__(host, port, timeout=TIMEOUT_SECONDS)
        self._scheme = scheme
        self._address = address

    def connect(self) -> None:
        sock = socket.create_connection((self._address, self.port), self.timeout)
        if self._scheme == "https":
            sock = ssl.create_default_context().wrap_socket(sock, server_hostname=self.host)
        self.sock = sock
