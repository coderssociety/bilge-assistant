"""Prices as sources write them and as they are spoken: "6.383,95" or "$3.995,89" in, "6.383,95" (Turkish) or
"6,383.95" (English) out, and how old a kept price is."""

import re
from datetime import timedelta

from bilge.core.language import AssistantLanguage

_NUMBER = re.compile(r"\d[\d.,]*")


def turkish_number(value: object) -> float | None:
    """ "6.383,95", "$3.995,89", "6.423" (thousands), "80,15", or a number already."""
    if isinstance(value, bool):
        return None
    if isinstance(value, int | float):
        return float(value)
    found = _NUMBER.search(str(value or ""))
    if found is None:
        return None
    whole, _, fraction = found.group(0).rstrip(".,").partition(",")
    try:
        return float(f"{whole.replace('.', '')}.{fraction or '0'}")
    except ValueError:
        return None


def amount(value: float, language: AssistantLanguage) -> str:
    """Two decimals with the language's separators: 6.383,95 / 6,383.95."""
    formatted = f"{value:,.2f}"
    if language is AssistantLanguage.TURKISH:
        formatted = formatted.replace(",", "\x00").replace(".", ",").replace("\x00", ".")
    return formatted


def age(elapsed: timedelta, language: AssistantLanguage) -> str:
    """ "25 dakika", "3 saat", "2 days": how long ago a kept price was fetched."""
    minutes = max(1, int(elapsed.total_seconds() // 60))
    english = language is AssistantLanguage.ENGLISH
    if minutes < 60:
        return f"{minutes} minute{'s' if minutes != 1 else ''}" if english else f"{minutes} dakika"
    hours = minutes // 60
    if hours < 48:
        return f"{hours} hour{'s' if hours != 1 else ''}" if english else f"{hours} saat"
    return f"{hours // 24} days" if english else f"{hours // 24} gün"
