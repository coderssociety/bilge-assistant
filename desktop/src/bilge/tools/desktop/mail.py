"""E-mail through the Outlook that is open: reading the unread messages or one picked out by sender or place, and
sending one after the user has heard exactly who it goes to and what it says."""

import re
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from bilge.core import mail_request
from bilge.core.language import AssistantLanguage
from bilge.desktop.windows.office import INBOX, MAIL_ITEM, OfficeError, Outlook, each, smtp_address
from bilge.tools.base import Risk, Tool, ToolError
from bilge.tools.desktop.common import int_argument, integer, obj, string_argument, text

LISTED = 5
# Messages whose text is read; each is cut, so a newsletter can't fill the answer.
READ_MESSAGES = 3
MAX_READ_CHARACTERS = 1500
# One message asked for by name or place is read further.
ONE_MESSAGE_CHARACTERS = 4000
MAX_POSITION = 50
# A name in an Outlook filter keeps only these, so it can't change the filter itself.
_FILTER_UNSAFE = re.compile(r"[^\w .@-]")
# The whole message is read out before it is sent; a longer one is refused rather than cut short in the question.
MAX_BODY = 600

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "read": "Outlook'taki okunmamış e-postaları sayar, en yenilerinin gönderenini ve konusunu, istenirse ne "
        "yazdıklarını söyler.",
        "content": "E-postaların ne yazdığı, içeriği isteniyorsa true",
        "sender": "Kimden gelen e-posta: 'Ahmet'in mailini oku' → 'Ahmet'; söylenmediyse boş bırak",
        "position": "Kaçıncı e-posta, en yeniden: 'son mailimi oku' → 1, 'ikinci maili oku' → 2",
        "one": "E-posta: {sender} - {subject}, {when}\n{body}",
        "no_sender": "'{sender}' kişisinden gelen bir e-posta bulamadım.",
        "empty": "Gelen kutun boş.",
        "only": "Yalnızca {count} e-posta buldum.",
        "message": "E-posta {number}: {sender} - {subject}\n{body}",
        "not_running": "Outlook açık değil.",
        "new_outlook": "Yeni Outlook dışarıdan yönetilemiyor; klasik Outlook'un açık olması gerekiyor.",
        "too_long": "Bu e-posta sesle onaylamak için çok uzun; daha kısa söyler misin?",
        "no_address": "'{to}' için bir e-posta adresi bulamadım.",
        "failed": "Outlook'a ulaşamadım.",
        "none": "Okunmamış e-postan yok.",
        "unread": "{count} okunmamış e-postan var. En yeniler: {list}",
        "send": "Outlook ile e-posta gönderir. Alıcı adres defterindeki bir ad ya da e-posta adresi olabilir.",
        "to": "Alıcının adı ya da e-posta adresi",
        "subject": "Konu",
        "body": "E-postanın metni, kullanıcının söylediği gibi",
        "unknown": "Outlook'ta '{to}' diye birini bulamadım.",
        "question": "{name} ({address}) adresine '{subject}' konulu e-postayı göndereyim mi? Metin: {body}",
        "sent": "E-postayı {name} adresine gönderdim.",
    },
    AssistantLanguage.ENGLISH: {
        "read": "Counts the unread e-mails in Outlook and says who sent the newest ones, their subjects and, when "
        "asked, what they say.",
        "content": "True when the user wants to hear what the e-mails say",
        "sender": "Whose e-mail: 'read Anna's email' → 'Anna'; leave empty if not said",
        "position": "Which e-mail, newest first: 'read my latest email' → 1, 'the second email' → 2",
        "one": "E-mail: {sender} - {subject}, {when}\n{body}",
        "no_sender": "I couldn't find an e-mail from '{sender}'.",
        "empty": "Your inbox is empty.",
        "only": "I found only {count} e-mails.",
        "message": "E-mail {number}: {sender} - {subject}\n{body}",
        "not_running": "Outlook isn't open.",
        "new_outlook": "The new Outlook can't be controlled from outside; classic Outlook needs to be open.",
        "too_long": "That e-mail is too long to confirm by voice; could you say it shorter?",
        "no_address": "I couldn't find an e-mail address for '{to}'.",
        "failed": "I couldn't reach Outlook.",
        "none": "You have no unread e-mail.",
        "unread": "You have {count} unread e-mails. The newest: {list}",
        "send": "Sends an e-mail with Outlook. The recipient can be a name from the address book or an address.",
        "to": "The recipient's name or e-mail address",
        "subject": "The subject",
        "body": "The message, as the user said it",
        "unknown": "I couldn't find '{to}' in Outlook.",
        "question": "Shall I send the e-mail '{subject}' to {name} ({address})? It says: {body}",
        "sent": "I sent the e-mail to {name}.",
    },
}


@dataclass(frozen=True)
class _Draft:
    name: str
    address: str
    subject: str
    body: str


def sender_filter(name: str) -> str:
    """Outlook's DASL filter for mail whose sender's name or address contains `name`, which is already stripped of
    anything but letters, digits, spaces and . @ - _."""
    like = "LIKE '%" + name.replace("'", "''") + "%'"
    return '@SQL="urn:schemas:httpmail:fromname" ' + like + ' OR "urn:schemas:httpmail:fromemail" ' + like


def mail_tools(outlook: Outlook, language: AssistantLanguage) -> list[Tool]:
    texts = _TEXTS[language]
    # The resolved recipient behind the last question, so what is sent is what the user heard.
    pending: dict[str, _Draft] = {}
    # Why the last question found nobody, said when the send is attempted.
    problem: list[str] = []

    def guarded(action):
        try:
            return outlook.call(action)
        except OfficeError as error:
            raise ToolError(texts.get(error.reason, texts["failed"])) from error

    def read_one(sender: str, position: int) -> str:
        def pick(app) -> tuple[int, Any]:
            items = outlook.folder(app, INBOX).Items
            if sender:
                items = items.Restrict(sender_filter(sender))
            items.Sort("[ReceivedTime]", True)
            count = int(items.Count)
            chosen = next((m for n, m in zip(range(position), each(items), strict=False) if n == position - 1), None)
            return count, chosen

        count, message = guarded(pick)
        if message is None:
            if sender and not count:
                return texts["no_sender"].format(sender=sender)
            return texts["only"].format(count=count) if count else texts["empty"]
        received = getattr(message, "ReceivedTime", None)
        return texts["one"].format(
            sender=getattr(message, "SenderName", "") or "?", subject=getattr(message, "Subject", "") or "",
            when=f"{received:%d.%m.%Y %H:%M}" if isinstance(received, datetime) else "",
            body=(getattr(message, "Body", "") or "").strip()[:ONE_MESSAGE_CHARACTERS],
        )  # fmt: skip

    def read(arguments: dict[str, Any]) -> str:
        sender = _FILTER_UNSAFE.sub("", string_argument(arguments, "sender")).strip()
        position = int_argument(arguments, "position")
        if sender or position:
            # Read or not: "son mailimi oku" means the newest one even when everything was read.
            return read_one(sender, max(1, min(position or 1, MAX_POSITION)))
        with_content = bool(arguments.get("content"))

        def unread(app) -> tuple[int, list[str], list[str]]:
            items = outlook.folder(app, INBOX).Items.Restrict("[UnRead] = True")
            items.Sort("[ReceivedTime]", True)
            count = int(items.Count)
            newest = list(zip(range(LISTED), each(items), strict=False))
            # Reports and receipts in the inbox may have no sender.
            listed = [f"{getattr(m, 'SenderName', '') or '?'}: {getattr(m, 'Subject', '') or ''}" for _, m in newest]
            bodies = [
                texts["message"].format(number=n + 1, sender=getattr(m, "SenderName", "") or "?",
                                        subject=getattr(m, "Subject", "") or "",
                                        body=(getattr(m, "Body", "") or "").strip()[:MAX_READ_CHARACTERS])
                for n, m in newest[:READ_MESSAGES]
            ] if with_content else []  # fmt: skip
            return count, listed, bodies

        count, listed, bodies = guarded(unread)
        if not count:
            return texts["none"]
        return "\n\n".join([texts["unread"].format(count=count, list="; ".join(listed)), *bodies])

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        # "İçeriğini oku" asks for the text even when the model only lists the messages again; a sender or a place
        # said in the command wins over the model's.
        refined = {**arguments, "content": bool(arguments.get("content")) or mail_request.asks_for_content(command)}
        said_sender, said_position = mail_request.sender(command), mail_request.position(command)
        if said_sender:
            refined["sender"] = said_sender
        if said_position:
            refined["position"] = said_position
        return refined

    def key(arguments: dict[str, Any]) -> str:
        return repr(sorted((k, str(v)) for k, v in arguments.items()))

    def question(arguments: dict[str, Any]) -> str | None:
        pending.clear()
        problem.clear()
        to = string_argument(arguments, "to")

        def resolve(app) -> tuple[str, str] | None:
            item = app.CreateItem(MAIL_ITEM)
            recipient = item.Recipients.Add(to)
            if not recipient.Resolve():
                return None
            return str(recipient.Name), smtp_address(recipient) or ""

        if len(string_argument(arguments, "body")) > MAX_BODY:
            problem.append(texts["too_long"])
            return None
        try:
            found = guarded(resolve) if to else None
        except ToolError as error:
            problem.append(str(error))
            return None
        if found is None:
            return None
        if not found[1]:
            problem.append(texts["no_address"].format(to=to))
            return None
        body = string_argument(arguments, "body")
        draft = _Draft(found[0], found[1], string_argument(arguments, "subject"), body)
        pending[key(arguments)] = draft
        return texts["question"].format(name=draft.name, address=draft.address, subject=draft.subject, body=body)

    def send(arguments: dict[str, Any]) -> str:
        draft = pending.pop(key(arguments), None)
        if draft is None:
            # Nothing is sent that the user didn't hear named in a question.
            raise ToolError(problem[0] if problem else texts["unknown"].format(to=string_argument(arguments, "to")))

        def deliver(app) -> None:
            item = app.CreateItem(MAIL_ITEM)
            item.To = draft.address
            item.Subject = draft.subject
            item.Body = draft.body
            item.Send()

        guarded(deliver)
        return texts["sent"].format(name=draft.name)

    return [
        # Subjects and senders are written by whoever sent the mail.
        Tool(
            "readMail",
            texts["read"],
            run=read,
            parameters=obj(
                content={"type": "boolean", "description": texts["content"]},
                sender=text(texts["sender"]),
                position=integer(texts["position"], 1, MAX_POSITION),
            ),
            refine=refine,
            untrusted_output=True,
        ),
        Tool(
            "sendEmail",
            texts["send"],
            run=send,
            parameters=obj(
                ["to", "body"], to=text(texts["to"]), subject=text(texts["subject"]), body=text(texts["body"])
            ),
            risk=Risk.CONFIRM,
            confirmation=question,
        ),
    ]
