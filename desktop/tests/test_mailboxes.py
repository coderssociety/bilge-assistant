"""IMAP reading through the real imaplib, talking to a small scripted server instead of a socket."""

import imaplib
import re
from email.message import EmailMessage

import pytest

from bilge import mailboxes
from bilge.brain.agent import resolve
from bilge.core.language import AssistantLanguage
from bilge.tools.base import ToolError
from bilge.tools.builtin.mail import read_mail_tool

TR = AssistantLanguage.TURKISH


def _mail(sender: str, subject: str, body: str, date: str, html: bool = False) -> bytes:
    message = EmailMessage()
    message["From"] = sender
    message["To"] = "ben@example.org"
    message["Subject"] = subject
    message["Date"] = date
    if html:
        message.set_content(body, subtype="html")
    else:
        message.set_content(body)
    return message.as_bytes()


# UID, message, seen; the newest last.
INBOX = [
    (3, _mail("Ahmet <ahmet@example.org>", "Fatura", "Fatura ödendi.", "Tue, 13 Oct 2026 08:15:00 +0300"), True),
    (7, _mail("Ayşe Kaya <ayse@example.org>", "Rapor", "<html><body><p>Rapor ekte.</p><script>x()</script></body></html>", "Wed, 14 Oct 2026 17:00:00 +0300",
              html=True), False),
    (9, _mail("Ahmet <ahmet@example.org>", "Toplantı", "Yarın 10'da görüşelim.", "Thu, 15 Oct 2026 09:30:00 +0300"),
     False),
]  # fmt: skip


class ScriptedIMAP(imaplib.IMAP4):
    """Answers imaplib's commands from INBOX; `uid_last` names the UID after the literal, as some servers do."""

    def __init__(self, password: str = "secret", uid_last: bool = False):
        self.password = password
        self.uid_last = uid_last
        self.commands: list[str] = []
        self._out = bytearray()
        super().__init__("imap.example.org", 993)

    def open(self, host="", port=993, timeout=None):
        self.host, self.port = host, port
        self._out += b"* OK [CAPABILITY IMAP4rev1] ready\r\n"

    def read(self, size):
        data = bytes(self._out[:size])
        del self._out[:size]
        return data

    def readline(self):
        end = self._out.find(b"\n") + 1
        line = bytes(self._out[:end])
        del self._out[:end]
        return line

    def shutdown(self):
        pass

    def send(self, data):
        tag, _, rest = data.decode().strip().partition(" ")
        self.commands.append(rest)
        name = rest.split(" ")[0].upper()
        if name == "LOGIN":
            ok = rest.endswith(f'"{self.password}"')
            self._reply(tag, "OK" if ok else "NO [AUTHENTICATIONFAILED] Invalid credentials")
        elif name == "EXAMINE":
            self._out += f"* {len(INBOX)} EXISTS\r\n".encode()
            self._reply(tag, "OK [READ-ONLY]")
        elif rest.upper().startswith("UID SEARCH"):
            unseen = rest.upper().endswith("UNSEEN")
            uids = " ".join(str(uid) for uid, _, seen in INBOX if not (unseen and seen))
            self._out += f"* SEARCH {uids}\r\n".encode()
            self._reply(tag, "OK")
        elif rest.upper().startswith("UID FETCH"):
            self._fetch(rest)
            self._reply(tag, "OK")
        else:
            self._out += b"* CAPABILITY IMAP4rev1\r\n" if name == "CAPABILITY" else b"* BYE\r\n"
            self._reply(tag, "OK")

    def _reply(self, tag: str, status: str):
        self._out += f"{tag} {status} done\r\n".encode()

    def _fetch(self, command: str):
        wanted = {int(uid) for uid in command.split(" ")[2].split(",")}
        fields = re.search(r"HEADER\.FIELDS \(([^)]*)\)", command)
        for number, (uid, raw, _) in enumerate(INBOX, 1):
            if uid not in wanted:
                continue
            if fields is not None:
                names = fields.group(1).lower().split()
                head = raw.split(b"\n\n")[0].split(b"\n")
                content = b"\r\n".join(h for h in head if h.split(b":")[0].lower().decode() in names) + b"\r\n\r\n"
                section = f"BODY[HEADER.FIELDS ({fields.group(1)})]"
            else:
                content = raw[: int(re.search(r"<0\.(\d+)>", command).group(1))]
                section = "BODY[]<0>"
            uid_part = f"UID {uid} " if not self.uid_last else ""
            self._out += f"* {number} FETCH ({uid_part}{section} {{{len(content)}}}\r\n".encode() + content
            self._out += f" UID {uid})\r\n".encode() if self.uid_last else b")\r\n"


def mailbox(**server) -> tuple[mailboxes.IMAPMailbox, list]:
    opened = []

    def connect(host, port):
        opened.append(ScriptedIMAP(**server))
        return opened[-1]

    return mailboxes.IMAPMailbox("imap.example.org", "ayse", "secret", connect=connect), opened


def test_unread_mail_is_counted_listed_and_read_without_marking_it_read():
    box, opened = mailbox()
    read = read_mail_tool(lambda: box, TR)
    assert read.untrusted_output
    assert read.run({}) == "2 okunmamış e-postan var. En yeniler: Ahmet: Toplantı; Ayşe Kaya: Rapor"
    assert read.run(read.refine({}, "İçeriğini oku")) == (
        "2 okunmamış e-postan var. En yeniler: Ahmet: Toplantı; Ayşe Kaya: Rapor\n\n"
        "E-posta 1: Ahmet - Toplantı\nYarın 10'da görüşelim.\n\nE-posta 2: Ayşe Kaya - Rapor\nRapor ekte."
    )
    commands = [command for server in opened for command in server.commands]
    assert "EXAMINE INBOX" in commands
    assert not [c for c in commands if c.split(" ")[0] in ("SELECT", "STORE") or "BODY[" in c.replace("PEEK", "")]


@pytest.mark.parametrize("uid_last", [False, True])
def test_one_message_is_picked_out_by_sender_or_place(uid_last):
    box, _ = mailbox(uid_last=uid_last)
    read = read_mail_tool(lambda: box, TR)
    assert read.run(read.refine({}, "Ayşe'nin mailini oku")) == (
        "E-posta: Ayşe Kaya - Rapor, 14.10.2026 17:00\nRapor ekte."
    )
    assert read.run(read.refine({}, resolve("Ahmet'in ikinci mailini oku", TR))) == (
        "E-posta: Ahmet - Fatura, 13.10.2026 08:15\nFatura ödendi."
    )
    assert read.run(read.refine({}, "son mailimi oku")).startswith("E-posta: Ahmet - Toplantı")
    assert read.run({"position": 9}) == "Yalnızca 3 e-posta buldum."
    assert read.run({"sender": "Zeynep"}) == "'Zeynep' kişisinden gelen bir e-posta bulamadım."


def test_a_wrong_password_an_unreachable_server_and_no_account_are_explained():
    box, _ = mailbox(password="başka")
    with pytest.raises(ToolError, match="parolayı kabul etmedi"):
        read_mail_tool(lambda: box, TR).run({})

    def refuse(host, port):
        raise ConnectionRefusedError(61, "refused")

    down = mailboxes.IMAPMailbox("imap.example.org", "ayse", "secret", connect=refuse)
    with pytest.raises(ToolError, match="E-posta sunucusuna ulaşamadım"):
        read_mail_tool(lambda: down, TR).run({})
    with pytest.raises(ToolError, match="E-posta sekmesinden"):
        read_mail_tool(lambda: None, TR).run({})


def test_the_server_may_name_its_port():
    assert mailboxes.split_server("imap.example.org") == ("imap.example.org", 993)
    assert mailboxes.split_server("imaps://mail.example.org:1993/") == ("mail.example.org", 1993)
    with pytest.raises(mailboxes.MailError):
        mailboxes.split_server("mail.example.org:x")
