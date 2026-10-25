"""A long recording cut into pieces for Whisper and written down with the time each piece starts.

Whisper reads at most 30 seconds at a time, so the recording is cut into pieces of about that length. A cut in the
middle of a word loses it, so each piece ends at the quietest moment of its last few seconds.
"""

from dataclasses import dataclass

import numpy as np

SAMPLE_RATE = 16_000
CHUNK_SECONDS = 30.0
# How far back from the full length a quieter place to cut is looked for.
SEARCH_SECONDS = 5.0
FRAME_SECONDS = 0.1


@dataclass(frozen=True)
class Segment:
    # Seconds from the start of the recording.
    start: float
    text: str


@dataclass(frozen=True)
class Chunk:
    start: float
    samples: np.ndarray


def timestamp(seconds: float) -> str:
    """ "00:04:07"; hours are always written, so a transcript reads the same at any length."""
    whole = max(0, int(seconds))
    return f"{whole // 3600:02d}:{whole % 3600 // 60:02d}:{whole % 60:02d}"


def lines(segments: list[Segment]) -> list[str]:
    return [f"[{timestamp(segment.start)}] {segment.text.strip()}" for segment in segments if segment.text.strip()]


def quietest_cut(samples: np.ndarray, sample_rate: int = SAMPLE_RATE, search_seconds: float = SEARCH_SECONDS,
                 frame_seconds: float = FRAME_SECONDS) -> int:  # fmt: skip
    """Where to end a piece: the middle of the quietest short frame in its last seconds, else its full length."""
    frame = max(1, int(frame_seconds * sample_rate))
    search = min(len(samples), int(search_seconds * sample_rate))
    count = search // frame
    if count < 2:
        return len(samples)
    begin = len(samples) - count * frame
    frames = samples[begin:].astype(np.float64).reshape(count, frame)
    quietest = int(np.argmin(np.mean(frames * frames, axis=1)))
    return begin + quietest * frame + frame // 2


class ChunkPlanner:
    """Collects audio as it comes (the microphone's small blocks, or a file decoded part by part) and hands back
    pieces of about `chunk_seconds`, each with the time it starts."""

    def __init__(self, sample_rate: int = SAMPLE_RATE, chunk_seconds: float = CHUNK_SECONDS):
        self.sample_rate = sample_rate
        self.chunk_size = int(chunk_seconds * sample_rate)
        self._pending: list[np.ndarray] = []
        self._pending_count = 0
        self._consumed = 0

    @property
    def elapsed(self) -> float:
        """Seconds of audio received so far."""
        return (self._consumed + self._pending_count) / self.sample_rate

    def add(self, samples: np.ndarray) -> list[Chunk]:
        if len(samples) == 0:
            return []
        self._pending.append(np.asarray(samples, dtype=np.float32))
        self._pending_count += len(samples)
        chunks: list[Chunk] = []
        while self._pending_count >= self.chunk_size:
            audio = np.concatenate(self._pending)
            cut = quietest_cut(audio[: self.chunk_size], self.sample_rate)
            chunks.append(Chunk(self._consumed / self.sample_rate, audio[:cut]))
            self._consumed += cut
            rest = audio[cut:]
            self._pending, self._pending_count = ([rest] if len(rest) else []), len(rest)
        return chunks

    def flush(self) -> Chunk | None:
        """What is left at the end, shorter than a full piece."""
        if not self._pending_count:
            return None
        chunk = Chunk(self._consumed / self.sample_rate, np.concatenate(self._pending))
        self._consumed += self._pending_count
        self._pending, self._pending_count = [], 0
        return chunk
