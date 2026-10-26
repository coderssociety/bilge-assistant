from datetime import datetime

import pytest

from bilge.core.tools.calendar_span import Kind, Span, span

THURSDAY = datetime(2026, 10, 15, 14, 5)


@pytest.mark.parametrize(
    ("command", "english", "expected"),
    [
        ("cuma ne var", False, Span(Kind.DAY, 1, 1)),
        ("haftaya pazartesi ne var", False, Span(Kind.DAY, 11, 1)),
        ("yarın takvimde ne var", False, Span(Kind.DAY, 1, 1)),
        ("önümüzdeki hafta ne var", False, Span(Kind.NEXT_WEEK, 4, 7)),
        ("haftaya neler var", False, Span(Kind.NEXT_WEEK, 4, 7)),
        ("bu hafta ne var", False, Span(Kind.THIS_WEEK, 0, 7)),
        ("15 Kasım'da ne var", False, Span(Kind.DAY, 31, 1)),
        ("takvimde ne var", False, None),
        ("what's on next week", True, Span(Kind.NEXT_WEEK, 4, 7)),
        ("what do I have on Friday", True, Span(Kind.DAY, 1, 1)),
        ("anything this week", True, Span(Kind.THIS_WEEK, 0, 7)),
        ("what's on my calendar", True, None),
    ],
)
def test_reads_the_days_a_calendar_question_covers(command, english, expected):
    assert span(command, THURSDAY, english) == expected
