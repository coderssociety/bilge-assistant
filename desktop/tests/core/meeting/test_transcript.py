import numpy as np

from bilge.core.meeting.transcript import SAMPLE_RATE, ChunkPlanner, Segment, lines, quietest_cut, timestamp


def tone(seconds: float, volume: float = 0.5) -> np.ndarray:
    t = np.arange(int(seconds * SAMPLE_RATE)) / SAMPLE_RATE
    return (np.sin(2 * np.pi * 220 * t) * volume).astype(np.float32)


def test_timestamps_always_show_hours():
    assert timestamp(0) == "00:00:00"
    assert timestamp(247.9) == "00:04:07"
    assert timestamp(3 * 3600 + 61) == "03:01:01"
    assert timestamp(-3) == "00:00:00"


def test_transcript_lines_carry_their_start_and_skip_empty_pieces():
    segments = [Segment(0, " Merhaba. "), Segment(30, ""), Segment(61.5, "Bütçeyi konuşalım.")]
    assert lines(segments) == ["[00:00:00] Merhaba.", "[00:01:01] Bütçeyi konuşalım."]


def test_a_piece_ends_in_the_quietest_moment_of_its_last_seconds():
    audio = np.concatenate([tone(27), np.zeros(int(0.5 * SAMPLE_RATE), dtype=np.float32), tone(2.5)])
    cut = quietest_cut(audio)
    assert 27 * SAMPLE_RATE <= cut <= 27.5 * SAMPLE_RATE


def test_a_piece_too_short_to_search_is_kept_whole():
    audio = tone(0.1)
    assert quietest_cut(audio) == len(audio)


def test_the_planner_hands_back_pieces_with_their_start_times():
    planner = ChunkPlanner(chunk_seconds=10)
    chunks = [chunk for _ in range(25) for chunk in planner.add(tone(1))]
    tail = planner.flush()
    assert tail is not None and planner.flush() is None
    pieces = [*chunks, tail]
    assert len(chunks) >= 2
    assert all(5 * SAMPLE_RATE <= len(chunk.samples) <= 10 * SAMPLE_RATE for chunk in chunks)
    starts = [chunk.start for chunk in pieces]
    assert starts == [sum(len(c.samples) for c in pieces[:i]) / SAMPLE_RATE for i in range(len(pieces))]
    assert sum(len(chunk.samples) for chunk in pieces) == 25 * SAMPLE_RATE and planner.elapsed == 25


def test_a_silent_gap_becomes_the_cut():
    planner = ChunkPlanner(chunk_seconds=10)
    chunks = planner.add(np.concatenate([tone(8), np.zeros(SAMPLE_RATE, dtype=np.float32), tone(3)]))
    assert len(chunks) == 1
    assert 8 * SAMPLE_RATE <= len(chunks[0].samples) <= 9 * SAMPLE_RATE
