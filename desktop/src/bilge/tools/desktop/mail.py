"""E-mail through the Outlook that is open: reading it (tools/builtin/mail.py), and sending a message or answering
the one just read after the user has heard exactly who it goes to and what it says."""

import html
import re
from dataclasses import dataclass
from typing import Any

from bilge import mailboxes
from bilge.core import mail_request
from bilge.core.language import AssistantLanguage
from bilge.desktop.windows.office import MAIL_ITEM, OfficeError, Outlook, OutlookMailbox, smtp_address
from bilge.tools.base import Risk, Tool, ToolError
from bilge.tools.builtin.contacts import ContactLookup
from bilge.tools.builtin.mail import MAX_POSITION, read_mail_tool
from bilge.tools.desktop.common import int_argument, integer, obj, string_argument, text
from bilge.tools.reading import TextReading

# The whole message is read out before it is sent; a longer one is refused rather than cut short in the question.
MAX_BODY = 600
# Outlook's olFormatHTML.
HTML_FORMAT = 2
_BODY_TAG = re.compile(r"<body[^>]*>", re.IGNORECASE)

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "not_running": "Outlook açık değil.",
        "new_outlook": "Yeni Outlook dışarıdan yönetilemiyor; klasik Outlook'un açık olması gerekiyor.",
        "too_long": "Bu e-posta sesle onaylamak için çok uzun; daha kısa söyler misin?",
        "no_address": "'{to}' için bir e-posta adresi bulamadım.",
        "failed": "Outlook'a ulaşamadım.",
        "send": "Outlook ile e-posta gönderir. Alıcı adres defterindeki ya da Kişiler'deki bir ad ya da e-posta adresi "
        "olabilir ('Ahmet'e mail at: …').",
        "to": "Alıcının adı ya da e-posta adresi",
        "subject": "Konu",
        "body": "E-postanın metni, kullanıcının söylediği gibi",
        "unknown": "Outlook'ta '{to}' diye birini bulamadım.",
        "question": "{name} ({address}) adresine '{subject}' konulu e-postayı göndereyim mi? Metin: {body}",
        "sent": "E-postayı {name} adresine gönderdim.",
        "reply": "Az önce okunan e-postaya Outlook ile yanıt verir ('buna yanıt ver: yarın uygunum', 'Ahmet'in "
        "mailine teşekkür ederim diye cevap yaz'). Metin yalnızca kullanıcının söylediği kelimelerdir.",
        "reply_body": "Yanıtın metni, kullanıcının söylediği kelimelerle; e-postadaki hiçbir metni ekleme",
        "reply_sender": "Kimin e-postasına: 'Ahmet'in mailine' → 'Ahmet'; söylenmediyse boş bırak",
        "reply_position": "Az önce okunanlardan kaçıncısına: 'ikincisine yanıt ver' → 2",
        "reply_question": "{name} ({address}) adresine '{subject}' konulu yanıtı göndereyim mi? Metin: {body}",
        "replied": "Yanıtı {name} adresine gönderdim.",
        "no_text": "Yanıtta ne yazmamı istediğini anlayamadım; örneğin 'buna yanıt ver: yarın uygunum' diyebilirsin.",
        "nothing_read": "Önce bir e-posta okumam gerekiyor; hangisine yanıt vereyim?",
        "which": "Az önce birden çok e-posta okudum: {list}. Hangisine yanıt vereyim?",
        "no_sender": "'{sender}' kişisinden gelen bir e-posta bulamadım.",
        "changed": "E-postanın göndereni artık farklı görünüyor; yanıtı göndermedim.",
    },
    AssistantLanguage.ENGLISH: {
        "not_running": "Outlook isn't open.",
        "new_outlook": "The new Outlook can't be controlled from outside; classic Outlook needs to be open.",
        "too_long": "That e-mail is too long to confirm by voice; could you say it shorter?",
        "no_address": "I couldn't find an e-mail address for '{to}'.",
        "failed": "I couldn't reach Outlook.",
        "send": "Sends an e-mail with Outlook. The recipient can be a name from the address book or the contacts, or "
        "an address ('email Anna: …').",
        "to": "The recipient's name or e-mail address",
        "subject": "The subject",
        "body": "The message, as the user said it",
        "unknown": "I couldn't find '{to}' in Outlook.",
        "question": "Shall I send the e-mail '{subject}' to {name} ({address})? It says: {body}",
        "sent": "I sent the e-mail to {name}.",
        "reply": "Replies with Outlook to the e-mail just read ('reply to it: I'm free tomorrow', 'answer Anna's "
        "email saying thanks'). The text is only the words the user said.",
        "reply_body": "The reply, in the user's own words; add nothing from the e-mail",
        "reply_sender": "Whose e-mail: 'Anna's email' → 'Anna'; leave empty if not said",
        "reply_position": "Which of the e-mails just read: 'reply to the second one' → 2",
        "reply_question": "Shall I send the reply '{subject}' to {name} ({address})? It says: {body}",
        "replied": "I sent the reply to {name}.",
        "no_text": "I didn't get what the reply should say; you could say, for example, 'reply: I'm free tomorrow'.",
        "nothing_read": "I need to read an e-mail first; which one should I answer?",
        "which": "I just read several e-mails: {list}. Which one should I answer?",
        "no_sender": "I couldn't find an e-mail from '{sender}'.",
        "changed": "The e-mail's sender looks different now; I didn't send the reply.",
    },
}


@dataclass(frozen=True)
class _Draft:
    name: str
    address: str
    subject: str
    body: str


@dataclass(frozen=True)
class _Reply:
    entry: str
    name: str
    address: str
    subject: str
    body: str


def mail_tools(
    outlook: Outlook,
    language: AssistantLanguage,
    reading: TextReading | None = None,
    contacts: ContactLookup | None = None,
) -> list[Tool]:
    """`contacts` finds the address of someone Outlook's own address book doesn't resolve."""
    texts = _TEXTS[language]
    # The resolved recipient behind the last question, so what is sent is what the user heard.
    pending: dict[str, _Draft] = {}
    replies: dict[str, _Reply] = {}
    # Why the last question found nobody, said when the send is attempted.
    problem: list[str] = []
    # The messages just read out or named, newest first: what "buna yanıt ver" answers.
    recent: list[mailboxes.MailMessage] = []

    def remember(messages: list[mailboxes.MailMessage]) -> None:
        recent[:] = messages

    def guarded(action):
        try:
            return outlook.call(action)
        except OfficeError as error:
            raise ToolError(texts.get(error.reason, texts["failed"])) from error

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
            if found is None and to and contacts is not None:
                person = contacts.find(to)
                found = (person.name, person.email or "") if person is not None else None
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

    def reply_refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        said = mail_request.reply_text(command)
        refined = {**arguments, "body": said or mail_request.only_said(string_argument(arguments, "body"), command)}
        sender = mail_request.sender(command)
        return {**refined, "sender": sender} if sender else refined

    def answered(arguments: dict[str, Any]) -> mailboxes.MailMessage:
        sender = string_argument(arguments, "sender")
        position = int_argument(arguments, "position")
        if sender:
            found = [m for m in recent if mailboxes.sender_matches(sender, m.sender, m.address)]
            if found:
                return found[0]
            try:
                _, message = OutlookMailbox(outlook).message(sender, 1)
            except mailboxes.MailError as error:
                raise ToolError(texts.get(error.reason, texts["failed"])) from error
            if message is None:
                raise ToolError(texts["no_sender"].format(sender=sender))
            return message
        if position and 1 <= position <= len(recent):
            return recent[position - 1]
        if len(recent) == 1:
            return recent[0]
        if not recent:
            raise ToolError(texts["nothing_read"])
        raise ToolError(texts["which"].format(list="; ".join(f"{m.sender}: {m.subject}" for m in recent)))

    def reply_question(arguments: dict[str, Any]) -> str | None:
        replies.clear()
        problem.clear()
        body = string_argument(arguments, "body")
        try:
            if not body:
                raise ToolError(texts["no_text"])
            if len(body) > MAX_BODY:
                raise ToolError(texts["too_long"])
            message = answered(arguments)
            name, address, subject = guarded(lambda app: _recipient(_reply(app, message.reference)))
            if not address:
                raise ToolError(texts["no_address"].format(to=name or message.sender))
        except ToolError as error:
            problem.append(str(error))
            return None
        draft = _Reply(message.reference, name, address, subject, body)
        replies[key(arguments)] = draft
        return texts["reply_question"].format(name=name, address=address, subject=subject, body=body)

    def reply(arguments: dict[str, Any]) -> str:
        draft = replies.pop(key(arguments), None)
        if draft is None:
            # Nothing is sent that the user didn't hear in a question.
            raise ToolError(problem[0] if problem else texts["nothing_read"])

        def deliver(app) -> None:
            answer = _reply(app, draft.entry)
            if _recipient(answer)[1] != draft.address:
                raise OfficeError("changed")
            _put_text(answer, draft.body)
            answer.Send()

        guarded(deliver)
        return texts["replied"].format(name=draft.name)

    return [
        read_mail_tool(lambda: OutlookMailbox(outlook), language, on_read=remember, reading=reading),
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
        Tool(
            "replyToEmail",
            texts["reply"],
            run=reply,
            parameters=obj(
                ["body"], body=text(texts["reply_body"]), sender=text(texts["reply_sender"]),
                position=integer(texts["reply_position"], 1, MAX_POSITION),
            ),
            risk=Risk.CONFIRM,
            confirmation=reply_question,
            refine=reply_refine,
        ),
    ]  # fmt: skip


def _reply(app, entry: str):
    """A new, unsent reply to the message: Outlook addresses it and quotes the original."""
    return app.GetNamespace("MAPI").GetItemFromID(entry).Reply()


def _recipient(answer) -> tuple[str, str, str]:
    recipient = answer.Recipients.Item(1)
    return str(recipient.Name or ""), smtp_address(recipient) or "", str(answer.Subject or "")


def _put_text(answer, body: str) -> None:
    """The user's words above the quoted message, in the reply's own format."""
    if int(getattr(answer, "BodyFormat", 0) or 0) == HTML_FORMAT:
        page = str(answer.HTMLBody or "")
        paragraph = "<p>" + html.escape(body).replace("\n", "<br>") + "</p>"
        tag = _BODY_TAG.search(page)
        answer.HTMLBody = page[: tag.end()] + paragraph + page[tag.end() :] if tag else paragraph + page
    else:
        answer.Body = body + "\r\n\r\n" + str(answer.Body or "")
