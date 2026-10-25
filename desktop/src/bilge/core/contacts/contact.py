"""A person from the address book, and finding the one a spoken name means ("Ahmet'in numarası" → "Ahmet Yılmaz")."""

from dataclasses import dataclass

from bilge.core.tools import phone_number, phrase_matcher


@dataclass(frozen=True)
class Contact:
    name: str
    phones: tuple[str, ...] = ()
    emails: tuple[str, ...] = ()
    nicknames: tuple[str, ...] = ()

    @property
    def phone(self) -> str | None:
        """The first number a message can go to, with its country code."""
        return next((found for found in map(phone_number.normalized, self.phones) if found), None)

    @property
    def email(self) -> str | None:
        return next((address for address in self.emails if "@" in address), None)


def find(spoken: str, contacts: list[Contact]) -> Contact | None:
    """By full name or nickname, tolerating Turkish endings ("Ayşe'nin") and a first name alone."""
    names: list[str] = []
    owners: list[Contact] = []
    for contact in contacts:
        for name in (contact.name, *contact.nicknames):
            if name.strip():
                names.append(name)
                owners.append(contact)
    match = phrase_matcher.best_match(spoken, names)
    return owners[names.index(match)] if match is not None else None
