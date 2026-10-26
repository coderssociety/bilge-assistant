"""Days as said aloud: "bugün", "dün", "yarın", or "26 Ekim Pazartesi" / "Monday 26 October"."""

from datetime import datetime

from bilge.core.language import AssistantLanguage

_TURKISH_MONTHS = (
    "Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık",
)  # fmt: skip
_TURKISH_WEEKDAYS = ("Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar")
_ENGLISH_MONTHS = (
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
)  # fmt: skip
_ENGLISH_WEEKDAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")


def day_phrase(day: datetime, today: datetime, language: AssistantLanguage) -> str:
    """ "bugün", "dün", "yarın", or "26 Ekim Pazartesi" / "Monday 26 October"."""
    english = language is AssistantLanguage.ENGLISH
    offset = (day.date() - today.date()).days
    relative = {0: ("today", "bugün"), -1: ("yesterday", "dün"), 1: ("tomorrow", "yarın")}.get(offset)
    if relative:
        return relative[0 if english else 1]
    if english:
        return f"{_ENGLISH_WEEKDAYS[day.weekday()]} {day.day} {_ENGLISH_MONTHS[day.month - 1]}"
    return f"{day.day} {_TURKISH_MONTHS[day.month - 1]} {_TURKISH_WEEKDAYS[day.weekday()]}"


def dated_phrase(day: datetime, today: datetime, language: AssistantLanguage) -> str:
    """Like `day_phrase`, but a day in another year is said with its year: "14 Kasım 2025" / "14 November 2025"."""
    if day.year == today.year or abs((day.date() - today.date()).days) <= 1:
        return day_phrase(day, today, language)
    if language is AssistantLanguage.ENGLISH:
        return f"{day.day} {_ENGLISH_MONTHS[day.month - 1]} {day.year}"
    return f"{day.day} {_TURKISH_MONTHS[day.month - 1]} {day.year}"
