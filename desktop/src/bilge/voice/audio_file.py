"""Reading recordings (m4a, mp3, wav, the sound of an mp4) as 16 kHz mono audio for Whisper, through PyAV, part by
part, so an hours-long file is never held in memory at once."""

from collections.abc import Iterator
from pathlib import Path

import av
import numpy as np

from bilge.voice.recognizers import SAMPLE_RATE

AUDIO_SUFFIXES = frozenset({"m4a", "mp3", "wav", "mp4", "ogg", "oga", "opus", "flac", "aac", "webm", "mov", "wma"})
BLOCK_SECONDS = 10.0


class AudioFileError(Exception):
    pass


def is_audio(path: Path) -> bool:
    return path.suffix.lower().lstrip(".") in AUDIO_SUFFIXES


def decode(path: Path, block_seconds: float = BLOCK_SECONDS) -> Iterator[np.ndarray]:
    """Blocks of about `block_seconds`, float32 in [-1, 1]."""
    block = int(block_seconds * SAMPLE_RATE)
    resampler = av.AudioResampler(format="flt", layout="mono", rate=SAMPLE_RATE)
    pending: list[np.ndarray] = []
    count = 0
    try:
        with av.open(str(path), metadata_errors="ignore") as container:
            if not container.streams.audio:
                raise AudioFileError(f"{path.name} has no sound")
            for frame in container.decode(audio=0):
                for converted in resampler.resample(frame):
                    pending.append(converted.to_ndarray().reshape(-1))
                    count += pending[-1].size
                if count >= block:
                    yield np.concatenate(pending)
                    pending, count = [], 0
            for converted in resampler.resample(None):
                pending.append(converted.to_ndarray().reshape(-1))
    except av.FFmpegError as error:
        raise AudioFileError(f"{path.name} could not be read: {error}") from error
    if pending:
        yield np.concatenate(pending)
