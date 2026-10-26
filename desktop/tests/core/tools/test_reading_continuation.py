from datetime import datetime

import pytest

from bilge.core.tools import reading_continuation

NOW = datetime(2026, 10, 15, 14, 5)


@pytest.mark.parametrize(
    ("command", "continues"),
    [
        ("devamını oku", True),
        ("Bilge devam et", True),
        ("sonrası", True),
        ("geri kalanını anlat", True),
        ("peki devamı?", True),
        ("read on", True),
        ("continue", True),
        ("please keep reading", True),
        ("müziğe devam et", False),
        ("belgeyi oku", False),
        ("devam eden işleri listele", False),
    ],
)
def test_knows_a_request_to_read_on(command, continues):
    assert reading_continuation.asks_to_continue(command) is continues


def test_parts_follow_each_other_without_cutting_words():
    text = " ".join(f"kelime{n}" for n in range(100))
    part, reading = reading_continuation.first("Rapor", text, 50, NOW)
    assert (part.number, part.has_more) == (1, True)
    assert part.text.endswith(("0", "1", "2", "3", "4", "5", "6", "7", "8", "9")) and len(part.text) <= 50
    told = [part.text]
    while part.has_more:
        part, reading = reading_continuation.following(reading, NOW)
        told.append(part.text)
    assert " ".join(told) == text
    last, _ = reading_continuation.following(reading, NOW)
    assert last.text == "" and not last.has_more


def test_a_reading_ages_out():
    _, reading = reading_continuation.first("x", "kısa", 50, NOW)
    assert reading_continuation.is_recent(reading, NOW)
    assert not reading_continuation.is_recent(reading, NOW + reading_continuation.CONTINUATION_WINDOW)
    assert not reading_continuation.is_recent(None, NOW)
