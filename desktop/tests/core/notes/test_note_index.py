from pathlib import Path

import pytest

from bilge.core.notes.note_index import NoteEntry, file_name, find, recent, title


def entry(name: str, modified: float) -> NoteEntry:
    return NoteEntry(name, Path(f"{name}-{modified}.md"), modified)


def test_the_heading_names_a_note_and_the_file_name_otherwise():
    assert title("# Alışveriş\n", "alisveris") == "Alışveriş"
    assert title("## Toplantı notları", "x") == "Toplantı notları"
    assert title("süt, yumurta", "market") == "market"
    assert title("#", "boş") == "boş"


def test_a_spoken_name_finds_the_note_changed_last_among_same_names():
    entries = [entry("Alışveriş", 1), entry("Toplantı", 5), entry("Alışveriş", 9)]
    assert find("alışveriş", entries) == entries[2]
    assert find("toplantının", entries) == entries[1]
    assert find("tatil", entries) is None


def test_recent_skips_unnamed_notes_and_keeps_the_newest_first():
    entries = [entry("A", 1), entry(" ", 10), entry("B", 3)]
    assert [e.name for e in recent(entries, 5)] == ["B", "A"]
    assert [e.name for e in recent(entries, 1)] == ["B"]


@pytest.mark.parametrize(
    ("note_title", "taken", "expected"),
    [
        ("Alışveriş", set(), "Alışveriş.md"),
        ("Alışveriş", {"alışveriş.md"}, "Alışveriş 2.md"),
        ("Alışveriş", {"Alışveriş.md", "Alışveriş 2.md"}, "Alışveriş 3.md"),
        ("a/b: c?", set(), "a b c.md"),
        ("../../etc/passwd", set(), "etc passwd.md"),
        ("CON", set(), "Not CON.md"),
        ("...", set(), "Not.md"),
    ],
)
def test_file_names_are_safe_and_never_reuse_a_name(note_title, taken, expected):
    assert file_name(note_title, taken) == expected


def test_long_titles_are_cut():
    assert len(file_name("x" * 300, set())) == 80 + len(".md")
