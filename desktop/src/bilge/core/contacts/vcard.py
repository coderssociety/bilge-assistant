"""The parts of vCards (RFC 6350, and the older 3.0) an assistant needs: name, nicknames, phone numbers and e-mail
addresses."""

from bilge.core.contacts.contact import Contact

_ESCAPES = {"n": "\n", "N": "\n", ",": ",", ";": ";", "\\": "\\"}


def parse(text: str) -> list[Contact]:
    """Every card in the text; cards without any name are skipped."""
    contacts = []
    card: list[tuple[str, str]] | None = None
    for line in _unfolded(text):
        name, value = _property(line)
        if name == "BEGIN" and value.upper() == "VCARD":
            card = []
        elif name == "END" and value.upper() == "VCARD":
            if card is not None:
                contact = _contact(card)
                if contact is not None:
                    contacts.append(contact)
            card = None
        elif card is not None and name:
            card.append((name, value))
    return contacts


def _unfolded(text: str) -> list[str]:
    """A line starting with a space or tab continues the one before it."""
    lines: list[str] = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        elif raw.strip():
            lines.append(raw)
    return lines


def _property(line: str) -> tuple[str, str]:
    """("TEL", "+90…") from "item1.TEL;TYPE=CELL:+90…"; the colon may also appear inside a quoted parameter."""
    quoted = False
    for index, character in enumerate(line):
        if character == '"':
            quoted = not quoted
        elif character == ":" and not quoted:
            head, value = line[:index], line[index + 1 :]
            name = head.split(";", 1)[0].rsplit(".", 1)[-1].strip().upper()
            return name, value.strip()
    return "", ""


def _unescaped(value: str) -> str:
    result = []
    characters = iter(value)
    for character in characters:
        if character == "\\":
            following = next(characters, "")
            result.append(_ESCAPES.get(following, following))
        else:
            result.append(character)
    return "".join(result)


def _split(value: str, separator: str) -> list[str]:
    """Splits on separators that aren't escaped, then unescapes each part."""
    parts, current, escaped = [], [], False
    for character in value:
        if escaped:
            current.append("\\" + character)
            escaped = False
        elif character == "\\":
            escaped = True
        elif character == separator:
            parts.append(_unescaped("".join(current)))
            current = []
        else:
            current.append(character)
    parts.append(_unescaped("".join(current)))
    return parts


def _contact(card: list[tuple[str, str]]) -> Contact | None:
    values: dict[str, list[str]] = {}
    for name, value in card:
        values.setdefault(name, []).append(value)
    name = next((_unescaped(v).strip() for v in values.get("FN", []) if _unescaped(v).strip()), "")
    if not name and values.get("N"):
        # Family; given; additional; prefixes; suffixes.
        parts = [*_split(values["N"][0], ";"), "", ""]
        name = " ".join(part.strip() for part in (parts[1], parts[0]) if part.strip())
    if not name and values.get("ORG"):
        name = _split(values["ORG"][0], ";")[0].strip()
    if not name:
        return None
    phones = tuple(p for p in (_unescaped(v).removeprefix("tel:").strip() for v in values.get("TEL", [])) if p)
    emails = tuple(e for e in (_unescaped(v).removeprefix("mailto:").strip() for v in values.get("EMAIL", [])) if e)
    nicknames = tuple(n.strip() for v in values.get("NICKNAME", []) for n in _split(v, ",") if n.strip())
    return Contact(name, phones, emails, nicknames)
