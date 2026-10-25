"""Reading e-mail: how many unread messages there are and from whom, what they say when asked, or one message picked
out by sender or place. The mailbox is Outlook on Windows or an IMAP account elsewhere."""

from collections.abc import Callable
from typing import Any

from bilge import mailboxes
from bilge.core import mail_request
from bilge.core.language import AssistantLanguage
from bilge.tools.base import Tool, ToolError
from bilge.tools.desktop.common import int_argument, integer, obj, string_argument, text

LISTED = 5
# Messages whose text is read; each is cut, so a newsletter can't fill the answer.
READ_MESSAGES = 3
MAX_READ_CHARACTERS = 1500
# One message asked for by name or place is read further.
ONE_MESSAGE_CHARACTERS = 4000
MAX_POSITION = 50

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "read": "Okunmamış e-postaları sayar, en yenilerinin gönderenini ve konusunu, istenirse ne yazdıklarını "
        "söyler; gönderene ya da sıraya göre tek bir e-postayı da okur.",
        "content": "E-postaların ne yazdığı, içeriği isteniyorsa true",
        "sender": "Kimden gelen e-posta: 'Ahmet'in mailini oku' → 'Ahmet'; söylenmediyse boş bırak",
        "position": "Kaçıncı e-posta, en yeniden: 'son mailimi oku' → 1, 'ikinci maili oku' → 2",
        "one": "E-posta: {sender} - {subject}, {when}\n{body}",
        "no_sender": "'{sender}' kişisinden gelen bir e-posta bulamadım.",
        "empty": "Gelen kutun boş.",
        "only": "Yalnızca {count} e-posta buldum.",
        "message": "E-posta {number}: {sender} - {subject}\n{body}",
        "none": "Okunmamış e-postan yok.",
        "unread": "{count} okunmamış e-postan var. En yeniler: {list}",
        "not_configured": "E-posta bağlı değil. Bilge Ayarları'ndaki E-posta sekmesinden bağlayabilirsin.",
        "not_running": "Outlook açık değil.",
        "new_outlook": "Yeni Outlook dışarıdan yönetilemiyor; klasik Outlook'un açık olması gerekiyor.",
        "outlook_failed": "Outlook'a ulaşamadım.",
        "login": "E-posta sunucusu kullanıcı adını ya da parolayı kabul etmedi.",
        "failed": "E-posta sunucusuna ulaşamadım.",
    },
    AssistantLanguage.ENGLISH: {
        "read": "Counts the unread e-mails and says who sent the newest ones, their subjects and, when asked, what "
        "they say; also reads one e-mail picked out by sender or place.",
        "content": "True when the user wants to hear what the e-mails say",
        "sender": "Whose e-mail: 'read Anna's email' → 'Anna'; leave empty if not said",
        "position": "Which e-mail, newest first: 'read my latest email' → 1, 'the second email' → 2",
        "one": "E-mail: {sender} - {subject}, {when}\n{body}",
        "no_sender": "I couldn't find an e-mail from '{sender}'.",
        "empty": "Your inbox is empty.",
        "only": "I found only {count} e-mails.",
        "message": "E-mail {number}: {sender} - {subject}\n{body}",
        "none": "You have no unread e-mail.",
        "unread": "You have {count} unread e-mails. The newest: {list}",
        "not_configured": "No e-mail account is connected. You can connect one on the Mail tab of Bilge Settings.",
        "not_running": "Outlook isn't open.",
        "new_outlook": "The new Outlook can't be controlled from outside; classic Outlook needs to be open.",
        "outlook_failed": "I couldn't reach Outlook.",
        "login": "The mail server refused the user name or password.",
        "failed": "I couldn't reach the mail server.",
    },
}


def read_mail_tool(mailbox: Callable[[], mailboxes.Mailbox | None], language: AssistantLanguage) -> Tool:
    texts = _TEXTS[language]

    def guarded(action: Callable[[mailboxes.Mailbox], Any]) -> Any:
        found = mailbox()
        if found is None:
            raise ToolError(texts["not_configured"])
        try:
            return action(found)
        except mailboxes.MailError as error:
            raise ToolError(texts.get(error.reason, texts["failed"])) from error

    def read_one(sender: str, position: int) -> str:
        count, message = guarded(lambda box: box.message(sender, position))
        if message is None:
            if sender and not count:
                return texts["no_sender"].format(sender=sender)
            return texts["only"].format(count=count) if count else texts["empty"]
        return texts["one"].format(
            sender=message.sender or "?", subject=message.subject,
            when=f"{message.received:%d.%m.%Y %H:%M}" if message.received else "",
            body=message.body[:ONE_MESSAGE_CHARACTERS],
        )  # fmt: skip

    def read(arguments: dict[str, Any]) -> str:
        sender = string_argument(arguments, "sender")
        position = int_argument(arguments, "position")
        if sender or position:
            # Read or not: "son mailimi oku" means the newest one even when everything was read.
            return read_one(sender, max(1, min(position or 1, MAX_POSITION)))
        bodies = READ_MESSAGES if arguments.get("content") else 0
        count, newest = guarded(lambda box: box.unread(LISTED, bodies))
        if not count:
            return texts["none"]
        listed = "; ".join(f"{m.sender or '?'}: {m.subject}" for m in newest)
        read_out = [
            texts["message"].format(number=n + 1, sender=m.sender or "?", subject=m.subject,
                                    body=m.body[:MAX_READ_CHARACTERS])
            for n, m in enumerate(newest[:bodies])
        ]  # fmt: skip
        return "\n\n".join([texts["unread"].format(count=count, list=listed), *read_out])

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

    # Subjects and senders are written by whoever sent the mail.
    return Tool(
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
    )
