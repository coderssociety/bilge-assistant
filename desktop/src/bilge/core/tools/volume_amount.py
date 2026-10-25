"""Reads how much the volume should change, or to what, from what was said ("sesi yüzde 20 artır", "yüzde 80'e
çıkar", "turn it up by 15 percent"), so the number never depends on the model."""

import re
from dataclasses import dataclass

_MAX = 100
# The number, then a dative ending ("80'e", "50'ye") that makes it the level to reach.
_NUMBER = r"(\d{1,3})(?!\d)('?(?:y?[ea])(?![^\W\d_]))?"
_PATTERNS = (
    re.compile(r"(?<![^\W\d_])(?:yüzde|%)\s*" + _NUMBER, re.IGNORECASE),
    re.compile(r"(?<![\d'])" + r"(\d{1,3})\s*(?:%|percent|puan|birim)(?![^\W\d_])()", re.IGNORECASE),
    re.compile(r"(?<![^\W\d_])by\s+(\d{1,3})(?!\d)()", re.IGNORECASE),
)
_TO = re.compile(r"(?<![^\W\d_])to\s+(\d{1,3})(?!\d)", re.IGNORECASE)


@dataclass(frozen=True)
class Amount:
    value: int
    # The level to reach ("yüzde 80'e", "to 80") rather than how much to change it.
    target: bool


def read(text: str) -> Amount | None:
    to = _TO.search(text)
    if to is not None:
        return Amount(min(int(to.group(1)), _MAX), target=True)
    for pattern in _PATTERNS:
        found = pattern.search(text)
        if found is not None:
            return Amount(min(int(found.group(1)), _MAX), target=bool(found.group(2)))
    return None
