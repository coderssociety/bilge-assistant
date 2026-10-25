"""Finds a known name in a spoken command ("İzmir'de", "Galatasaray'ın", "THY hissesi"), allowing the Turkish case
endings that follow a proper name but not a longer word that merely starts with it ("Kars" is not "karşı")."""

from collections.abc import Iterable

from bilge.core.text import folded

# Folded, as `folded` leaves them: "İzmir'in" → "izmirin", "Ankara'daki" → "ankaradaki".
ENDINGS = frozenset(
    {"", "da", "de", "ta", "te", "dan", "den", "tan", "ten", "daki", "deki", "taki", "teki", "a", "e", "ya", "ye",
     "in", "un", "nin", "nun", "la", "le", "yla", "yle", "ca", "ce"}
)  # fmt: skip


def find[T](command: str, names: Iterable[tuple[str, T]], endings: frozenset[str] = ENDINGS) -> T | None:
    """The value of the longest name said; names are given in any spelling and compared folded. `endings`: the
    suffixes allowed after a name, for names that also take others ("Power FM'i aç")."""
    words = folded(command).split()
    best: tuple[int, T] | None = None
    for name, value in names:
        key = folded(name).split()
        if key and (best is None or len(" ".join(key)) > best[0]) and _said(words, key, endings):
            best = (len(" ".join(key)), value)
    return best[1] if best else None


def _said(words: list[str], key: list[str], endings: frozenset[str]) -> bool:
    for start in range(len(words) - len(key) + 1):
        *leading, last = key
        if words[start : start + len(leading)] != leading:
            continue
        word = words[start + len(leading)]
        if word.startswith(last) and word[len(last) :] in endings:
            return True
    return False
