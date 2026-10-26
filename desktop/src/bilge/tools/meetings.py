"""The meeting tools: start and stop recording a meeting, write down an audio file, and read the summary just made.

Writing down a file takes minutes, so it runs on its own thread and Bilge says when it is done; meanwhile it goes on
answering. A recording's notes are offered to be read right after they are saved ("Özetini okuyayım mı?").
"""

import logging
import threading
from collections.abc import Callable
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from bilge.brain.routing import Rule, rule
from bilge.core.language import AssistantLanguage
from bilge.core.meeting import meeting_command, meeting_notes
from bilge.desktop import file_search
from bilge.desktop.base import Folders
from bilge.tools.base import Tool, ToolError
from bilge.tools.desktop.common import obj, string_argument, text
from bilge.voice import audio_file
from bilge.voice.meeting import MeetingNotes, MeetingRecorder, Notes, NotRecording, transcribe_blocks
from bilge.voice.recognizers import Recognizer

log = logging.getLogger(__name__)

# How long after the notes are saved a "yes" or "özeti oku" still reads their summary.
OFFER_WINDOW = timedelta(minutes=5)
MAX_FOUND = 20

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "start": "Toplantı kaydını başlatır: mikrofonun duyduklarını kayıt bitene kadar yazıya döker, sonunda özetiyle "
        "Belgeler/Bilge/Toplantılar klasörüne kaydeder.",
        "started": "Toplantıyı kaydediyorum. Bitirmek için 'kaydı bitir' de; o zamana kadar başka bir şeye "
        "karışmıyorum.",
        "already": "Zaten bir toplantıyı kaydediyorum. Bitirmek için 'kaydı bitir' de.",
        "stop": "Toplantı kaydını bitirir; dökümü ve özeti Belgeler/Bilge/Toplantılar klasörüne kaydeder.",
        "not_recording": "Şu an kaydettiğim bir toplantı yok.",
        "saved": "Kaydı bitirdim. Notları Belgeler/Bilge/Toplantılar klasörüne '{name}' adıyla kaydettim. Özetini "
        "okuyayım mı?",
        "saved_without_summary": "Kaydı bitirdim ve dökümü Belgeler/Bilge/Toplantılar klasörüne '{name}' adıyla "
        "kaydettim, ama özetini çıkaramadım; dil modeline ulaşamadım.",
        "saved_empty": "Kaydı bitirdim ama konuşma duymadım; notu yine de '{name}' adıyla kaydettim.",
        "save_failed": "Notları kaydedemedim: {error}",
        "transcribe": "Bir ses ya da video dosyasını (m4a, mp3, wav, mp4) yazıya döker ve özetiyle "
        "Belgeler/Bilge/Toplantılar klasörüne kaydeder. Uzun sürer; bitince haber verir.",
        "query": "Dosya adında geçen kelimeler; 'son indirdiğim ses kaydı' ya da 'bu ses dosyası' gibi isteklerde boş "
        "bırak",
        "no_audio": "'{query}' adında bir ses dosyası bulamadım.",
        "no_download": "İndirilenler klasöründe bir ses dosyası bulamadım.",
        "busy": "Zaten bir dosyayı yazıya döküyorum; bitince haber vereceğim.",
        "transcribing": "'{name}' dosyasını yazıya döküyorum; uzun sürebilir, bitince haber vereceğim.",
        "file_done": "'{name}' dosyasını yazıya döktüm ve notları Belgeler/Bilge/Toplantılar klasörüne '{notes}' "
        "adıyla kaydettim. Özetini dinlemek istersen 'Bilge, özeti oku' de.",
        "file_without_summary": "'{name}' dosyasını yazıya döktüm ve Belgeler/Bilge/Toplantılar klasörüne '{notes}' "
        "adıyla kaydettim, ama özetini çıkaramadım; dil modeline ulaşamadım.",
        "file_empty": "'{name}' dosyasında konuşma duymadım.",
        "file_failed": "'{name}' dosyasını yazıya dökemedim.",
        "read": "Az önce kaydedilen toplantı notlarının özetini okur.",
        "no_summary": "Okuyabileceğim yeni bir toplantı özeti yok.",
    },
    AssistantLanguage.ENGLISH: {
        "start": "Starts recording a meeting: writes down what the microphone hears until the recording is stopped, "
        "then saves it with a summary in Documents/Bilge/Toplantılar.",
        "started": "I'm recording the meeting. Say 'stop recording' to finish; until then I'll stay out of it.",
        "already": "I'm already recording a meeting. Say 'stop recording' to finish.",
        "stop": "Stops recording the meeting and saves the transcript and summary in Documents/Bilge/Toplantılar.",
        "not_recording": "I'm not recording a meeting right now.",
        "saved": "Recording stopped. I saved the notes in Documents/Bilge/Toplantılar as '{name}'. Shall I read the "
        "summary?",
        "saved_without_summary": "Recording stopped and I saved the transcript in Documents/Bilge/Toplantılar as "
        "'{name}', but I couldn't summarize it; I couldn't reach the language model.",
        "saved_empty": "Recording stopped, but I heard no speech; I saved the note as '{name}' anyway.",
        "save_failed": "I couldn't save the notes: {error}",
        "transcribe": "Transcribes an audio or video file (m4a, mp3, wav, mp4) and saves it with a summary in "
        "Documents/Bilge/Toplantılar. It takes a while; Bilge says when it's done.",
        "query": "Words in the file name; leave empty for 'my latest audio download' or 'this audio file'",
        "no_audio": "I couldn't find an audio file called '{query}'.",
        "no_download": "I couldn't find an audio file in Downloads.",
        "busy": "I'm already transcribing a file; I'll tell you when it's done.",
        "transcribing": "I'm transcribing '{name}'; it may take a while, and I'll tell you when it's done.",
        "file_done": "I transcribed '{name}' and saved the notes in Documents/Bilge/Toplantılar as '{notes}'. Say "
        "'Bilge, read the summary' to hear it.",
        "file_without_summary": "I transcribed '{name}' and saved it in Documents/Bilge/Toplantılar as '{notes}', but "
        "I couldn't summarize it; I couldn't reach the language model.",
        "file_empty": "I heard no speech in '{name}'.",
        "file_failed": "I couldn't transcribe '{name}'.",
        "read": "Reads the summary of the meeting notes just saved.",
        "no_summary": "There's no new meeting summary to read.",
    },
}


class Meetings:
    def __init__(
        self,
        recorder: MeetingRecorder,
        notes: MeetingNotes,
        recognizer: Recognizer,
        folders: Folders,
        language: AssistantLanguage,
        announce: Callable[[str], None],
        clock: Callable[[], datetime] = datetime.now,
    ):
        self.recorder = recorder
        self.notes = notes
        self._recognizer = recognizer
        self._folders = folders
        self.language = language
        self.texts = _TEXTS[language]
        self._announce = announce
        self._clock = clock
        self._lock = threading.Lock()
        self._job: threading.Thread | None = None
        self._cancelled = threading.Event()
        self._offer: tuple[str, datetime] | None = None

    def start(self, _: dict[str, Any]) -> str:
        return self.texts["started"] if self.recorder.begin() else self.texts["already"]

    def stop(self, _: dict[str, Any]) -> str:
        try:
            notes = self.recorder.finish()
        except NotRecording:
            return self.texts["not_recording"]
        except OSError as error:
            raise ToolError(self.texts["save_failed"].format(error=error.strerror or error)) from error
        if notes.summary:
            self._offer = (notes.summary, self._clock())
            return self.texts["saved"].format(name=notes.path.name)
        return self.texts["saved_without_summary" if notes.problem else "saved_empty"].format(name=notes.path.name)

    def transcribe(self, arguments: dict[str, Any]) -> str:
        query = string_argument(arguments, "query")
        path = self._find(query) if query else self._newest_download()
        if path is None:
            raise ToolError(self.texts["no_audio"].format(query=query) if query else self.texts["no_download"])
        with self._lock:
            if self._job is not None and self._job.is_alive():
                return self.texts["busy"]
            self._job = threading.Thread(target=self._transcribe_file, args=(path,), name="bilge-transcribe",
                                         daemon=True)  # fmt: skip
            self._job.start()
        return self.texts["transcribing"].format(name=path.name)

    def read_summary(self, _: dict[str, Any]) -> str:
        offer, self._offer = self.offer(), None
        if offer is None:
            return self.texts["no_summary"]
        return meeting_notes.spoken(offer)

    def offer(self) -> str | None:
        """The summary just saved, while a yes still means "read it"."""
        offer = self._offer
        if offer is None or self._clock() - offer[1] > OFFER_WINDOW:
            return None
        return offer[0]

    def close(self) -> None:
        """Bilge stops listening: a file being written down is given up, so it no longer holds (or reloads) the
        model; nothing is announced for it."""
        self._cancelled.set()

    def _transcribe_file(self, path: Path) -> None:
        texts = self.texts
        cancelled = self._cancelled.is_set
        try:
            segments, seconds = transcribe_blocks(self._recognizer, audio_file.decode(path), self.language, cancelled)
            if cancelled():
                log.info("Writing down %s was given up", path)
                return
            if not segments:
                self._announce(texts["file_empty"].format(name=path.name))
                return
            notes = self.notes.write(self._clock(), seconds, segments, source=path.name)
        except Exception:  # noqa: BLE001 - on its own thread, so whatever stops it must still be told to the user
            if cancelled():
                log.info("Writing down %s stopped with listening", path, exc_info=True)
                return
            log.exception("Could not transcribe %s", path)
            self._announce(texts["file_failed"].format(name=path.name))
            return
        self._announce(self._file_done(path, notes))

    def _file_done(self, path: Path, notes: Notes) -> str:
        if not notes.summary:
            return self.texts["file_without_summary"].format(name=path.name, notes=notes.path.name)
        self._offer = (notes.summary, self._clock())
        return self.texts["file_done"].format(name=path.name, notes=notes.path.name)

    def _roots(self) -> list[Path]:
        folders = self._folders
        return [folders.downloads(), folders.desktop(), folders.documents(), folders.music(), folders.videos(),
                folders.home()]  # fmt: skip

    def _find(self, query: str) -> Path | None:
        # A link inside the home folder can point anywhere; only files that really live here count.
        home = self._folders.home().resolve()
        found = file_search.find(query, self._roots(), MAX_FOUND)
        return next((p for p in found if audio_file.is_audio(p) and p.resolve().is_relative_to(home)), None)

    def _newest_download(self) -> Path | None:
        try:
            items = [p for p in self._folders.downloads().iterdir() if p.is_file() and audio_file.is_audio(p)]
        except OSError:
            return None
        return next(iter(file_search.newest_first(items)), None)

    def tools(self) -> list[Tool]:
        texts = self.texts
        return [
            Tool("startMeetingRecording", texts["start"], run=self.start),
            Tool("stopMeetingRecording", texts["stop"], run=self.stop),
            # The file's name was chosen by whoever sent it.
            Tool(
                "transcribeAudioFile",
                texts["transcribe"],
                run=self.transcribe,
                parameters=obj(query=text(texts["query"])),
                untrusted_output=True,
            ),
            # The summary repeats what other people said.
            Tool("readMeetingSummary", texts["read"], run=self.read_summary, untrusted_output=True),
        ]

    def rules(self) -> list[Rule]:
        language = self.language
        return [
            rule("stopMeetingRecording", lambda c: self.recorder.active and meeting_command.is_stop(c, addressed=True)),
            rule("startMeetingRecording", meeting_command.is_start),
            rule(
                "transcribeAudioFile",
                lambda c: meeting_command.asks_file_transcription(c) and meeting_command.names_no_file(c),
                lambda _: {"query": ""},
            ),
            rule(
                "readMeetingSummary",
                lambda c: self.offer() is not None and meeting_command.asks_for_summary(c, language),
            ),
        ]
