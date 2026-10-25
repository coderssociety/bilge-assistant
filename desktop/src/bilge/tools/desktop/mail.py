"""E-mail through the Outlook that is open: reading it (tools/builtin/mail.py) and sending a message after the user
has heard exactly who it goes to and what it says."""

from dataclasses import dataclass
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.desktop.windows.office import MAIL_ITEM, OfficeError, Outlook, OutlookMailbox, smtp_address
from bilge.tools.base import Risk, Tool, ToolError
from bilge.tools.builtin.mail import read_mail_tool
from bilge.tools.desktop.common import obj, string_argument, text

# The whole message is read out before it is sent; a longer one is refused rather than cut short in the question.
MAX_BODY = 600

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "not_running": "Outlook açık değil.",
        "new_outlook": "Yeni Outlook dışarıdan yönetilemiyor; klasik Outlook'un açık olması gerekiyor.",
        "too_long": "Bu e-posta sesle onaylamak için çok uzun; daha kısa söyler misin?",
        "no_address": "'{to}' için bir e-posta adresi bulamadım.",
        "failed": "Outlook'a ulaşamadım.",
        "send": "Outlook ile e-posta gönderir. Alıcı adres defterindeki bir ad ya da e-posta adresi olabilir.",
        "to": "Alıcının adı ya da e-posta adresi",
        "subject": "Konu",
        "body": "E-postanın metni, kullanıcının söylediği gibi",
        "unknown": "Outlook'ta '{to}' diye birini bulamadım.",
        "question": "{name} ({address}) adresine '{subject}' konulu e-postayı göndereyim mi? Metin: {body}",
        "sent": "E-postayı {name} adresine gönderdim.",
    },
    AssistantLanguage.ENGLISH: {
        "not_running": "Outlook isn't open.",
        "new_outlook": "The new Outlook can't be controlled from outside; classic Outlook needs to be open.",
        "too_long": "That e-mail is too long to confirm by voice; could you say it shorter?",
        "no_address": "I couldn't find an e-mail address for '{to}'.",
        "failed": "I couldn't reach Outlook.",
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
        read_mail_tool(lambda: OutlookMailbox(outlook), language),
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
