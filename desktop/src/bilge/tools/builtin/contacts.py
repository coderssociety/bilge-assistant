"""Looking someone up in the address book ("Ahmet'in numarası ne", "Ayşe'nin e-postası"), and the lookup the tools
that send something use to find the address."""

from collections.abc import Callable
from typing import Any

from bilge import contacts
from bilge.core.contacts import contact as contact_match
from bilge.core.contacts.contact import Contact
from bilge.core.language import AssistantLanguage
from bilge.tools.base import Tool, ToolError
from bilge.tools.desktop.common import choice, obj, string_argument, text

DETAILS = ["phone", "email", "both"]

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "find": "Kişilerde birinin telefon numarasını ya da e-posta adresini bulup söyler ('Ahmet'in numarası ne', "
        "'Ayşe'nin e-postası').",
        "name": "Kişinin eksiz adı: 'Ahmet'in' → 'Ahmet'",
        "detail": "İstenen bilgi; belirtilmediyse both",
        "phone": "telefonu {value}",
        "no_phone": "kayıtlı telefonu yok",
        "email": "e-postası {value}",
        "no_email": "kayıtlı e-postası yok",
        "unknown": "Kişilerinde '{name}' adında birini bulamadım.",
        "no_name": "Kimi aradığını anlayamadım.",
        "not_configured": "Kişiler bağlı değil. Linux'ta Ayarlar → Takvim'deki CalDAV hesabının adres defteri "
        "kullanılır; Windows'ta Outlook'un kişileri.",
        "no_address_book": "Takvim sunucun bir adres defteri sunmuyor.",
        "login": "Adres defteri sunucusu kullanıcı adını ya da parolayı kabul etmedi.",
        "not_running": "Outlook açık değil.",
        "new_outlook": "Yeni Outlook dışarıdan yönetilemiyor; klasik Outlook'un açık olması gerekiyor.",
        "failed": "Adres defterine ulaşamadım.",
    },
    AssistantLanguage.ENGLISH: {
        "find": "Looks up someone's phone number or e-mail address in the contacts ('what's Anna's number', "
        "'Tom's email').",
        "name": "The person's name: 'Anna's' → 'Anna'",
        "detail": "What is wanted; both when not said",
        "phone": "phone {value}",
        "no_phone": "no phone number saved",
        "email": "e-mail {value}",
        "no_email": "no e-mail address saved",
        "unknown": "I couldn't find '{name}' in your contacts.",
        "no_name": "I didn't catch whom to look up.",
        "not_configured": "No contacts are connected. On Linux the address book of the CalDAV account under "
        "Settings → Calendar is used; on Windows, Outlook's contacts.",
        "no_address_book": "Your calendar server doesn't offer an address book.",
        "login": "The address book server refused the user name or password.",
        "not_running": "Outlook isn't open.",
        "new_outlook": "The new Outlook can't be controlled from outside; classic Outlook needs to be open.",
        "failed": "I couldn't reach the address book.",
    },
}


class ContactLookup:
    def __init__(self, source: Callable[[], contacts.ContactSource | None], language: AssistantLanguage):
        self.source = source
        self.texts = _TEXTS[language]

    def find(self, name: str) -> Contact | None:
        """The contact a spoken name means; ToolError, with what to tell the user, when the book can't be read."""
        found = self.source()
        if found is None:
            raise ToolError(self.texts["not_configured"])
        try:
            everyone = found.contacts()
        except contacts.ContactsError as error:
            raise ToolError(self.texts.get(error.reason, self.texts["failed"])) from error
        return contact_match.find(name, everyone)


def find_contact_tool(lookup: ContactLookup, language: AssistantLanguage) -> Tool:
    texts = _TEXTS[language]

    def run(arguments: dict[str, Any]) -> str:
        name = string_argument(arguments, "name")
        if not name:
            raise ToolError(texts["no_name"])
        found = lookup.find(name)
        if found is None:
            raise ToolError(texts["unknown"].format(name=name))
        detail = string_argument(arguments, "detail")
        parts = []
        if detail != "email":
            parts.append(texts["phone"].format(value=found.phones[0]) if found.phones else texts["no_phone"])
        if detail != "phone":
            parts.append(texts["email"].format(value=found.email) if found.email else texts["no_email"])
        return f"{found.name}: {', '.join(parts)}."

    return Tool(
        "findContact",
        texts["find"],
        run=run,
        parameters=obj(["name"], name=text(texts["name"]), detail=choice(DETAILS, texts["detail"])),
    )
