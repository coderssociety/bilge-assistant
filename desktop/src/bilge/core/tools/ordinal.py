"""Places in a list as said: "ikinci", "üçüncüsünü", "2'nci" (after turkish_number_parser), "sonuncu", "second",
"3rd", "last". Words are folded."""

import re

LAST = -1
# Turkish ones take endings ("üçüncüsünü"); "ilk" only short ones, not "ilkbahar".
_TURKISH = (("ilk", 1), ("birinci", 1), ("ikinci", 2), ("ucuncu", 3), ("dorduncu", 4), ("besinci", 5),
            ("altinci", 6), ("yedinci", 7), ("sekizinci", 8), ("dokuzuncu", 9), ("onuncu", 10),
            ("sonuncu", LAST))  # fmt: skip
_ENGLISH = {"first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8,
            "ninth": 9, "tenth": 10, "last": LAST}  # fmt: skip
_DIGITS = re.compile(r"^(\d+)(?:inci|nci|uncu|ncu|st|nd|rd|th)")
_SHORT_PREFIX = 5
_SHORT_ENDING = 3


def of_word(word: str) -> int | None:
    """The place one folded word names, LAST for the last one."""
    if word in _ENGLISH:
        return _ENGLISH[word]
    digits = _DIGITS.match(word)
    if digits is not None:
        return int(digits.group(1)) or None
    for prefix, place in _TURKISH:
        if word.startswith(prefix) and (len(prefix) >= _SHORT_PREFIX or len(word) <= len(prefix) + _SHORT_ENDING):
            return place
    return None


def in_words(words: list[str]) -> int | None:
    return next((place for place in map(of_word, words) if place is not None), None)
