"""The notes in Bilge's notes folder as names: which one a spoken name means, which changed last, and the file name a
new note gets."""

import re
from dataclasses import dataclass
from pathlib import Path

from bilge.core.tools import phrase_matcher

MAX_FILE_NAME = 80
# Characters no file system takes in a name, and control characters.
_UNSAFE = re.compile(r'[\\/:*?"<>|\x00-\x1f]')
# Windows refuses these as file names whatever the extension.
_RESERVED = frozenset(
    {"con", "prn", "aux", "nul", *(f"com{n}" for n in range(1, 10)), *(f"lpt{n}" for n in range(1, 10))}
)


@dataclass(frozen=True)
class NoteEntry:
    name: str
    path: Path
    modified: float


def title(first_line: str, stem: str) -> str:
    """A note's name: its "# heading" when the file starts with one, otherwise the file name."""
    line = first_line.strip()
    if line.startswith("#"):
        heading = line.lstrip("#").strip()
        if heading:
            return heading
    return stem


def recent(entries: list[NoteEntry], limit: int) -> list[NoteEntry]:
    """Named notes, most recently changed first."""
    return sorted((e for e in entries if e.name.strip()), key=lambda e: e.modified, reverse=True)[:limit]


def find(spoken: str, entries: list[NoteEntry]) -> NoteEntry | None:
    """The note a spoken name refers to; among notes of the same name, the one changed last."""
    by_recency = recent(entries, len(entries))
    name = phrase_matcher.best_match(spoken, [e.name for e in by_recency])
    return next((e for e in by_recency if e.name == name), None) if name else None


def file_name(note_title: str, taken: set[str]) -> str:
    """ "Alışveriş" → "Alışveriş.md"; a name already in `taken` (compared without case) gets a number."""
    base = " ".join(_UNSAFE.sub(" ", note_title).split()).strip(". ")[:MAX_FILE_NAME].strip(". ")
    if not base or base.lower() in _RESERVED:
        base = f"Not {base}".strip()
    lowered = {name.lower() for name in taken}
    candidate, number = f"{base}.md", 2
    while candidate.lower() in lowered:
        candidate, number = f"{base} {number}.md", number + 1
    return candidate
