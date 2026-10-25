"""Text messages through the user's phone ("Ahmet'e mesaj at: geliyorum"): on Linux by KDE Connect, after the user
has heard who it goes to, the number and the words. Windows has no such bridge yet, and says so."""

from dataclasses import dataclass
from typing import Any

from bilge.core import message_request
from bilge.core.language import AssistantLanguage
from bilge.core.tools import phone_number
from bilge.desktop.base import PairedPhone, TextMessages
from bilge.desktop.process import DesktopError, MissingProgram, NotPossibleHere
from bilge.tools.base import Risk, Tool, ToolError
from bilge.tools.builtin.contacts import ContactLookup
from bilge.tools.desktop.common import obj, string_argument, text

# The whole message is read out before it is sent; a longer one is refused rather than cut short in the question.
MAX_TEXT = 600

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "send": "Telefondan birine SMS gönderir ('Ahmet'e mesaj at: geliyorum'); göndermeden önce kime ne gideceğini "
        "okuyup onay ister.",
        "recipient": "Alıcının eksiz adı ya da telefon numarası: 'Ahmet'e' → 'Ahmet'",
        "text": "Mesajın metni, kullanıcının ağzından: 'geç kalacağımı yaz' → 'Geç kalacağım.'",
        "unavailable": "Windows'ta SMS gönderemiyorum; bu, Linux'ta KDE Connect ile eşleşmiş bir telefonla çalışıyor.",
        "no_bridge": "SMS için KDE Connect gerekiyor: kdeconnect-cli yüklü değil. Telefonu KDE Connect (ya da "
        "GSConnect) ile eşleştirince gönderebilirim.",
        "no_phone": "KDE Connect ile eşleşmiş ve şu an erişilebilen bir telefon yok.",
        "failed": "Telefona ulaşamadım; SMS gönderilmedi.",
        "no_text": "Mesajda ne yazmamı istediğini anlayamadım.",
        "too_long": "Bu mesaj sesle onaylamak için çok uzun; daha kısa söyler misin?",
        "no_number": "'{recipient}' için kayıtlı bir telefon numarası bulamadım.",
        "unknown": "Kişilerinde '{recipient}' adında birini bulamadım.",
        "question": "{name} ({number}) kişisine {phone} telefonundan şu SMS'i göndereyim mi: {text}",
        "sent": "SMS'i {name} kişisine gönderdim.",
    },
    AssistantLanguage.ENGLISH: {
        "send": "Sends a text message from the phone ('text Anna: on my way'); reads out who it goes to and what it "
        "says, and asks first.",
        "recipient": "The recipient's name or phone number: 'text Anna' → 'Anna'",
        "text": "The message, in the user's voice: 'tell her I'll be late' → 'I'll be late.'",
        "unavailable": "I can't send text messages on Windows; this works on Linux with a phone paired through KDE "
        "Connect.",
        "no_bridge": "Text messages need KDE Connect: kdeconnect-cli isn't installed. Once the phone is paired with KDE "
        "Connect (or GSConnect), I can send them.",
        "no_phone": "No phone paired through KDE Connect is reachable right now.",
        "failed": "I couldn't reach the phone; the message wasn't sent.",
        "no_text": "I didn't get what the message should say.",
        "too_long": "That message is too long to confirm by voice; could you say it shorter?",
        "no_number": "I couldn't find a phone number for '{recipient}'.",
        "unknown": "I couldn't find '{recipient}' in your contacts.",
        "question": "Shall I text {name} ({number}) from {phone}: {text}",
        "sent": "I sent the message to {name}.",
    },
}


@dataclass(frozen=True)
class _Draft:
    name: str
    number: str
    text: str
    phone: PairedPhone


def send_message_tool(messages: TextMessages | None, people: ContactLookup, language: AssistantLanguage) -> Tool:
    texts = _TEXTS[language]
    # The resolved message behind the last question, so what is sent is what the user heard.
    pending: dict[str, _Draft] = {}
    # Why the last question couldn't be asked, said when the send is attempted.
    problem: list[str] = []

    def key(arguments: dict[str, Any]) -> str:
        return repr(sorted((k, str(v)) for k, v in arguments.items()))

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        said = message_request.message_text(command)
        return {**arguments, "text": said} if said else arguments

    def reachable() -> PairedPhone:
        if messages is None:
            raise ToolError(texts["unavailable"])
        try:
            return messages.reachable_phone()
        except MissingProgram as error:
            raise ToolError(texts["no_bridge"]) from error
        except NotPossibleHere as error:
            raise ToolError(texts["no_phone"]) from error
        except DesktopError as error:
            raise ToolError(texts["failed"]) from error

    def recipient(spoken: str) -> tuple[str, str]:
        number = phone_number.normalized(spoken)
        if number is not None:
            return spoken, number
        person = people.find(spoken)
        if person is None:
            raise ToolError(texts["unknown"].format(recipient=spoken))
        if person.phone is None:
            raise ToolError(texts["no_number"].format(recipient=person.name))
        return person.name, person.phone

    def draft(arguments: dict[str, Any]) -> _Draft:
        through = reachable()
        said = string_argument(arguments, "text")
        if not said:
            raise ToolError(texts["no_text"])
        if len(said) > MAX_TEXT:
            raise ToolError(texts["too_long"])
        name, number = recipient(string_argument(arguments, "recipient"))
        return _Draft(name, number, said, through)

    def question(arguments: dict[str, Any]) -> str | None:
        pending.clear()
        problem.clear()
        try:
            found = draft(arguments)
        except ToolError as error:
            problem.append(str(error))
            return None
        pending[key(arguments)] = found
        return texts["question"].format(name=found.name, number=found.number, phone=found.phone.name, text=found.text)

    def send(arguments: dict[str, Any]) -> str:
        found = pending.pop(key(arguments), None)
        if found is None:
            # Nothing is sent that the user didn't hear in a question.
            raise ToolError(problem[0] if problem else texts["failed"])
        if messages is None:
            raise ToolError(texts["unavailable"])
        try:
            messages.send(found.phone, found.number, found.text)
        except DesktopError as error:
            raise ToolError(texts["failed"]) from error
        return texts["sent"].format(name=found.name)

    return Tool(
        "sendMessage",
        texts["send"],
        run=send,
        parameters=obj(["recipient", "text"], recipient=text(texts["recipient"]), text=text(texts["text"])),
        risk=Risk.CONFIRM,
        confirmation=question,
        refine=refine,
    )
