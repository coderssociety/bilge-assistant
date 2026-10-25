"""Meetings written down: recording what the microphone hears during a meeting, or reading a recording from a
file, transcribed piece by piece and saved with the model's summary under Documents/Bilge/Toplantılar.

Audio is captured only between the start and the stop command, and only its transcript is kept.
"""

import logging
import queue
import threading
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

import numpy as np

from bilge.core.language import AssistantLanguage
from bilge.core.meeting import meeting_notes
from bilge.core.meeting.transcript import Chunk, ChunkPlanner, Segment, lines
from bilge.llm.messages import Message
from bilge.llm.providers import ChatProvider, ProviderError
from bilge.voice.recognizers import Recognizer

log = logging.getLogger(__name__)

SUMMARY_TOKENS = 1500

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "unheard": "(Bu bölüm yazıya dökülemedi.)",
        "cut_short": "kayıt, Bilge kapanınca yarıda kaldı",
    },
    AssistantLanguage.ENGLISH: {
        "unheard": "(This part couldn't be transcribed.)",
        "cut_short": "the recording stopped when Bilge was switched off",
    },
}


class NotRecording(Exception):
    pass


@dataclass(frozen=True)
class Notes:
    path: Path
    # Empty when the model couldn't summarize; `problem` then says why.
    summary: str
    problem: str | None = None


class MeetingNotes:
    def __init__(
        self,
        provider: Callable[[], ChatProvider],
        documents: Callable[[], Path],
        language: AssistantLanguage,
        part_characters: int = meeting_notes.PART_CHARACTERS,
    ):
        self._provider = provider
        self._documents = documents
        self.language = language
        self._part_characters = part_characters

    def folder(self) -> Path:
        return self._documents().joinpath(*meeting_notes.FOLDER)

    def write(self, started: datetime, seconds: float, segments: list[Segment], source: str | None = None,
              problem: str | None = None) -> Notes:  # fmt: skip
        """`problem`: why no summary is asked for (the recording was cut short); the transcript is saved anyway."""
        summary = ""
        if problem is None and lines(segments):
            summary, problem = self._summary(segments)
        shown = summary or (meeting_notes.missing_summary(problem, self.language) if problem else "")
        text = meeting_notes.document(started, seconds, shown, segments, self.language, source)
        folder = self.folder()
        folder.mkdir(parents=True, exist_ok=True)
        path = _free_path(folder / meeting_notes.file_name(started))
        path.write_text(text, encoding="utf-8")
        log.info("Meeting notes saved to %s", path)
        return Notes(path, summary, problem)

    def _summary(self, segments: list[Segment]) -> tuple[str, str | None]:
        try:
            notes = [self._ask(meeting_notes.part_instructions(self.language), part)
                     for part in meeting_notes.parts(lines(segments), self._part_characters)]  # fmt: skip
            while len(notes) > 1:
                notes = [self._ask(meeting_notes.merge_instructions(self.language), "\n\n---\n\n".join(group))
                         for group in meeting_notes.groups(notes, self._part_characters)]  # fmt: skip
        except ProviderError as error:
            log.warning("Could not summarize the meeting: %s", error)
            return "", str(error)
        return notes[0].strip(), None

    def _ask(self, instructions: str, text: str) -> str:
        messages = [Message.system(instructions), Message.user(meeting_notes.wrapped(text))]
        reply = self._provider().complete(messages, None, temperature=0.2, max_tokens=SUMMARY_TOKENS)
        return reply.text


def _free_path(path: Path) -> Path:
    """A second meeting in the same minute gets "(2)" rather than replacing the first one's notes."""
    candidate, number = path, 2
    while candidate.exists():
        candidate = path.with_name(f"{path.stem} ({number}){path.suffix}")
        number += 1
    return candidate


def transcribed(recognizer: Recognizer, chunk: Chunk, language: AssistantLanguage) -> Segment | None:
    try:
        text = recognizer.transcribe(chunk.samples)
    except Exception:  # A piece that fails is marked in the transcript; the rest of the meeting still counts.
        log.exception("Could not transcribe the piece at %.0f s", chunk.start)
        text = _TEXTS[language]["unheard"]
    return Segment(chunk.start, text) if text.strip() else None


def transcribe_blocks(recognizer: Recognizer, blocks: Iterable[np.ndarray], language: AssistantLanguage,
                      cancelled: Callable[[], bool] = lambda: False) -> tuple[list[Segment], float]:  # fmt: skip
    """A whole recording, decoded part by part: its segments and its length in seconds."""
    planner = ChunkPlanner()
    segments: list[Segment] = []
    for block in blocks:
        if cancelled():
            break
        for chunk in planner.add(block):
            segment = transcribed(recognizer, chunk, language)
            segments = [*segments, segment] if segment else segments
    tail = planner.flush()
    segment = transcribed(recognizer, tail, language) if tail is not None and not cancelled() else None
    return ([*segments, segment] if segment else segments), planner.elapsed


@dataclass
class _Session:
    started: datetime
    planner: ChunkPlanner
    chunks: queue.Queue
    segments: list[Segment]
    cancelled: threading.Event
    worker: threading.Thread


class MeetingRecorder:
    """Takes the microphone's audio while a meeting is recorded and transcribes it on its own thread as each piece
    fills, so stopping only waits for the last piece."""

    def __init__(self, recognizer: Recognizer, notes: MeetingNotes, clock: Callable[[], datetime] = datetime.now):
        self._recognizer = recognizer
        self.notes = notes
        self._clock = clock
        self._lock = threading.Lock()
        self._session: _Session | None = None

    @property
    def active(self) -> bool:
        return self._session is not None

    def begin(self) -> bool:
        """False when a meeting is already being recorded."""
        with self._lock:
            if self._session is not None:
                return False
            chunks: queue.Queue[Chunk | None] = queue.Queue()
            segments: list[Segment] = []
            cancelled = threading.Event()
            worker = threading.Thread(target=self._work, args=(chunks, segments, cancelled), name="bilge-meeting",
                                      daemon=True)  # fmt: skip
            self._session = _Session(self._clock(), ChunkPlanner(), chunks, segments, cancelled, worker)
            worker.start()
            return True

    def add(self, samples: np.ndarray) -> None:
        """Called on the audio thread for every block; only queues full pieces."""
        with self._lock:
            session = self._session
            if session is None:
                return
            for chunk in session.planner.add(samples):
                session.chunks.put(chunk)

    def finish(self) -> Notes:
        """Ends the recording, waits for the last piece and saves the notes with the model's summary."""
        session = self._end()
        tail = session.planner.flush()
        if tail is not None:
            session.chunks.put(tail)
        session.chunks.put(None)
        session.worker.join()
        return self.notes.write(session.started, session.planner.elapsed, sorted(session.segments, key=_start))

    def abandon(self) -> Notes | None:
        """Bilge is being switched off: what was transcribed so far is saved at once, without waiting for the model."""
        try:
            session = self._end()
        except NotRecording:
            return None
        session.cancelled.set()
        session.chunks.put(None)
        problem = _TEXTS[self.notes.language]["cut_short"]
        segments = sorted(list(session.segments), key=_start)
        return self.notes.write(session.started, session.planner.elapsed, segments, problem=problem)

    def _end(self) -> _Session:
        with self._lock:
            session, self._session = self._session, None
        if session is None:
            raise NotRecording
        return session

    def _work(self, chunks: queue.Queue, segments: list[Segment], cancelled: threading.Event) -> None:
        while (chunk := chunks.get()) is not None:
            if cancelled.is_set():
                continue
            segment = transcribed(self._recognizer, chunk, self.notes.language)
            if segment is not None:
                segments.append(segment)


def _start(segment: Segment) -> float:
    return segment.start
