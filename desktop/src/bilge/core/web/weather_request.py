"""What a weather question asks about beyond the city and the day: a part of the day ("akşam yağmur var mı",
"tomorrow morning") and whether it is about rain ("yağmur yağacak mı", "do I need an umbrella")."""

from enum import StrEnum

from bilge.core import text


class PartOfDay(StrEnum):
    MORNING = "morning"
    NOON = "noon"
    AFTERNOON = "afternoon"
    EVENING = "evening"
    NIGHT = "night"


# Local hours [start, end) after midnight of the day asked about; the night runs into the next morning.
HOURS: dict[PartOfDay, tuple[int, int]] = {
    PartOfDay.MORNING: (6, 12),
    PartOfDay.NOON: (11, 14),
    PartOfDay.AFTERNOON: (12, 18),
    PartOfDay.EVENING: (18, 22),
    PartOfDay.NIGHT: (22, 30),
}
_TURKISH_PARTS = (("sabah", PartOfDay.MORNING), ("aksam", PartOfDay.EVENING), ("gece", PartOfDay.NIGHT),
                  ("ogle", PartOfDay.NOON))  # fmt: skip
_ENGLISH_PARTS = {
    "morning": PartOfDay.MORNING, "noon": PartOfDay.NOON, "midday": PartOfDay.NOON, "lunchtime": PartOfDay.NOON,
    "afternoon": PartOfDay.AFTERNOON, "evening": PartOfDay.EVENING, "tonight": PartOfDay.NIGHT,
    "night": PartOfDay.NIGHT,
}  # fmt: skip
_TURKISH_RAIN = ("yagmur", "yagis", "yagacak", "yagar", "yagiyor", "semsiye", "saganak", "islan")
_ENGLISH_RAIN = ("rain", "umbrella", "shower", "precipitation", "drizzl", "wet")


def part_of_day(command: str, english: bool) -> PartOfDay | None:
    words = text.folded(command).split()
    if english:
        return next((_ENGLISH_PARTS[w] for w in words if w in _ENGLISH_PARTS), None)
    for index, word in enumerate(words):
        if word.startswith("ogleden") and words[index + 1 : index + 2] == ["sonra"]:
            return PartOfDay.AFTERNOON
        for stem, part in _TURKISH_PARTS:
            # "Geçen" folds to "gecen" and is not the night.
            if word.startswith(stem) and word != "gecen":
                return part
    return None


def asks_about_rain(command: str, english: bool) -> bool:
    stems = _ENGLISH_RAIN if english else _TURKISH_RAIN
    return any(word.startswith(stems) for word in text.folded(command).split())
