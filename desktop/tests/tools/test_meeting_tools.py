import os
import threading
import time
import wave
from datetime import datetime, timedelta

import numpy as np
import pytest

from bilge.core.language import AssistantLanguage
from bilge.llm.messages import Reply
from bilge.tools.base import ToolError
from bilge.tools.meetings import Meetings
from bilge.voice.meeting import MeetingNotes, MeetingRecorder


class Provider:
    def complete(self, messages, tools=None, **_):
        return Reply("Bütçe konuşuldu.\n### Kararlar\n- Bütçe onaylandı.")

    def list_models(self):
        return []


class Recognizer:
    def transcribe(self, samples):
        return "Bütçeyi onaylıyoruz."


class Folders:
    def __init__(self, root):
        self.root = root

    def home(self):
        return self.root

    def desktop(self):
        return self.root / "Masaüstü"

    def downloads(self):
        return self.root / "İndirilenler"

    def documents(self):
        return self.root / "Belgeler"

    def music(self):
        return self.root / "Müzik"

    def videos(self):
        return self.root / "Videolar"


class Clock:
    def __init__(self):
        self.now = datetime(2026, 10, 25, 14, 30)

    def __call__(self):
        return self.now


def make(tmp_path, language=AssistantLanguage.TURKISH, recognizer=None):
    folders = Folders(tmp_path)
    for folder in (folders.downloads(), folders.documents()):
        folder.mkdir(parents=True, exist_ok=True)
    clock = Clock()
    notes = MeetingNotes(Provider, folders.documents, language)
    recorder = MeetingRecorder(Recognizer(), notes, clock=clock)
    announced = []
    done = threading.Event()

    def announce(text):
        announced.append(text)
        done.set()

    meetings = Meetings(recorder, notes, recognizer or Recognizer(), folders, language, announce, clock=clock)
    return meetings, announced, done, clock


def write_wav(path, seconds=1.0):
    t = np.arange(int(seconds * 16_000)) / 16_000
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(16_000)
        out.writeframes((np.sin(2 * np.pi * 300 * t) * 0.4 * 32767).astype("<i2").tobytes())


def claimed(meetings, command):
    return [route(command).name for route in meetings.rules() if route(command) is not None]


def test_a_recording_is_started_stopped_and_its_summary_offered(tmp_path):
    meetings, _, _, _ = make(tmp_path)
    assert claimed(meetings, "toplantıyı kaydetmeye başla") == ["startMeetingRecording"]
    assert claimed(meetings, "kaydı bitir") == []
    assert meetings.start({}).startswith("Toplantıyı kaydediyorum")
    assert meetings.start({}).startswith("Zaten")
    assert claimed(meetings, "kaydı bitir") == ["stopMeetingRecording"]
    meetings.recorder.add(np.full(16_000, 0.2, dtype=np.float32))
    reply = meetings.stop({})
    assert reply.startswith("Kaydı bitirdim") and "'2026-10-25 14.30.md'" in reply and reply.endswith("okuyayım mı?")
    assert (tmp_path / "Belgeler" / "Bilge" / "Toplantılar" / "2026-10-25 14.30.md").exists()
    assert claimed(meetings, "evet") == ["readMeetingSummary"]
    assert meetings.read_summary({}) == "Bütçe konuşuldu.\nKararlar:\n- Bütçe onaylandı."
    assert claimed(meetings, "evet") == []
    assert meetings.read_summary({}) == "Okuyabileceğim yeni bir toplantı özeti yok."


def test_stopping_without_a_recording_says_so(tmp_path):
    meetings, *_ = make(tmp_path)
    assert meetings.stop({}) == "Şu an kaydettiğim bir toplantı yok."


def test_the_summary_offer_lapses(tmp_path):
    meetings, _, _, clock = make(tmp_path)
    meetings.start({})
    meetings.stop({})
    clock.now += timedelta(minutes=6)
    assert claimed(meetings, "evet") == []


def test_the_newest_audio_download_is_transcribed_in_the_background(tmp_path):
    meetings, announced, done, _ = make(tmp_path)
    downloads = tmp_path / "İndirilenler"
    old, new = downloads / "eski.wav", downloads / "görüşme.wav"
    write_wav(old)
    write_wav(new)
    (downloads / "rapor.pdf").write_bytes(b"%PDF")
    os.utime(old, (time.time() - 100, time.time() - 100))
    assert claimed(meetings, "son indirdiğim ses kaydını yazıya dök") == ["transcribeAudioFile"]
    assert (
        meetings.transcribe({"query": ""})
        == "'görüşme.wav' dosyasını yazıya döküyorum; uzun sürebilir, bitince haber vereceğim."
    )
    assert done.wait(10)
    assert announced[0].startswith("'görüşme.wav' dosyasını yazıya döktüm")
    saved = (tmp_path / "Belgeler" / "Bilge" / "Toplantılar" / "2026-10-25 14.30.md").read_text(encoding="utf-8")
    assert "Kaynak: görüşme.wav" in saved and "[00:00:00] Bütçeyi onaylıyoruz." in saved
    assert claimed(meetings, "özeti oku") == ["readMeetingSummary"]


def test_a_named_file_is_found_by_its_name(tmp_path):
    meetings, announced, done, _ = make(tmp_path)
    (tmp_path / "Müzik").mkdir()
    write_wav(tmp_path / "Müzik" / "haftalık toplantı.wav")
    assert "haftalık toplantı.wav" in meetings.transcribe({"query": "haftalık"})
    assert done.wait(10)
    assert claimed(meetings, "haftalık toplantı kaydını yazıya dök") == []


def test_a_missing_or_broken_file_is_reported(tmp_path):
    meetings, announced, done, _ = make(tmp_path)
    with pytest.raises(ToolError, match="İndirilenler"):
        meetings.transcribe({"query": ""})
    with pytest.raises(ToolError, match="'yok'"):
        meetings.transcribe({"query": "yok"})
    (tmp_path / "İndirilenler" / "bozuk.mp3").write_bytes(b"not audio")
    meetings.transcribe({"query": ""})
    assert done.wait(10)
    assert announced == ["'bozuk.mp3' dosyasını yazıya dökemedim."]


def test_tools_are_described_in_english_too(tmp_path):
    meetings, *_ = make(tmp_path, AssistantLanguage.ENGLISH)
    names = [tool.name for tool in meetings.tools()]
    assert names == ["startMeetingRecording", "stopMeetingRecording", "transcribeAudioFile", "readMeetingSummary"]
    assert meetings.start({}).startswith("I'm recording the meeting")
    assert claimed(meetings, "stop recording") == ["stopMeetingRecording"]


class HeldRecognizer:
    """Waits inside its first transcription until `release` is set."""

    def __init__(self):
        self.calls = 0
        self.inside = threading.Event()
        self.release = threading.Event()

    def transcribe(self, samples):
        self.calls += 1
        self.inside.set()
        self.release.wait(10)
        return "Bütçeyi onaylıyoruz."


def test_closing_gives_up_a_file_being_written_down_without_a_word(tmp_path):
    recognizer = HeldRecognizer()
    meetings, announced, _, _ = make(tmp_path, recognizer=recognizer)
    write_wav(tmp_path / "İndirilenler" / "uzun.wav", seconds=120)
    meetings.transcribe({"query": ""})
    assert recognizer.inside.wait(10)
    meetings.close()
    recognizer.release.set()
    job = next(thread for thread in threading.enumerate() if thread.name == "bilge-transcribe")
    job.join(10)
    assert not job.is_alive() and recognizer.calls == 1 and announced == []
    assert not (tmp_path / "Belgeler" / "Bilge" / "Toplantılar").exists()
