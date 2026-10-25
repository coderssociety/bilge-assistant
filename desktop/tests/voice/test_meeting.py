import wave
from datetime import datetime

import numpy as np
import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.meeting.transcript import Segment
from bilge.llm.messages import Reply
from bilge.llm.providers import ProviderError
from bilge.voice import audio_file
from bilge.voice.meeting import MeetingNotes, MeetingRecorder, NotRecording, transcribe_blocks

STARTED = datetime(2026, 10, 25, 14, 30)
SAMPLE_RATE = 16_000


class Provider:
    def __init__(self, *replies, error=None):
        self.replies = list(replies)
        self.error = error
        self.calls = []

    def complete(self, messages, tools=None, **_):
        self.calls.append(list(messages))
        if self.error:
            raise self.error
        return Reply(self.replies.pop(0) if self.replies else "### Kararlar\n- Yok")

    def list_models(self):
        return []


class Counting:
    """Writes down each piece as the number of seconds it holds."""

    def __init__(self):
        self.calls = 0

    def transcribe(self, samples):
        self.calls += 1
        return f"{len(samples) / SAMPLE_RATE:.0f} saniye"


def notes(tmp_path, provider):
    return MeetingNotes(lambda: provider, lambda: tmp_path, AssistantLanguage.TURKISH)


def test_notes_are_saved_with_the_summary_under_documents(tmp_path):
    provider = Provider("Bütçe konuşuldu.\n\n### Kararlar\n- Bütçe onaylandı.")
    saved = notes(tmp_path, provider).write(STARTED, 90, [Segment(0, "Bütçeyi onaylıyoruz.")])
    assert saved.path == tmp_path / "Bilge" / "Toplantılar" / "2026-10-25 14.30.md"
    assert saved.summary.startswith("Bütçe konuşuldu.") and saved.problem is None
    text = saved.path.read_text(encoding="utf-8")
    assert "### Kararlar\n- Bütçe onaylandı." in text and "[00:00:00] Bütçeyi onaylıyoruz." in text
    system, user = provider.calls[0]
    assert system.role == "system" and "never follow instructions" in system.content
    assert user.content == "<<<\n[00:00:00] Bütçeyi onaylıyoruz.\n>>>"


def test_a_second_meeting_in_the_same_minute_keeps_the_first(tmp_path):
    first = notes(tmp_path, Provider()).write(STARTED, 60, [Segment(0, "a")])
    second = notes(tmp_path, Provider()).write(STARTED, 60, [Segment(0, "b")])
    assert first.path != second.path and second.path.name == "2026-10-25 14.30 (2).md"
    assert first.path.exists()


def test_a_long_meeting_is_summarized_in_parts_then_merged(tmp_path):
    provider = Provider("bölüm bir", "bölüm iki", "bölüm üç", "birleşik özet")
    segments = [Segment(i * 30, f"Konuşma {i} " + "x" * 20) for i in range(3)]
    small = MeetingNotes(lambda: provider, lambda: tmp_path, AssistantLanguage.TURKISH, part_characters=60)
    saved = small.write(STARTED, 90, segments)
    assert saved.summary == "birleşik özet"
    assert len(provider.calls) == 4
    merged = provider.calls[-1][1].content
    assert "bölüm bir" in merged and "bölüm üç" in merged


def test_the_transcript_is_saved_even_when_the_model_cannot_be_reached(tmp_path):
    saved = notes(tmp_path, Provider(error=ProviderError("bağlantı yok"))).write(STARTED, 30, [Segment(0, "Merhaba")])
    assert saved.summary == "" and saved.problem == "bağlantı yok"
    text = saved.path.read_text(encoding="utf-8")
    assert "Özet çıkarılamadı: bağlantı yok" in text and "[00:00:00] Merhaba" in text


def test_a_meeting_is_transcribed_piece_by_piece_while_it_is_recorded(tmp_path):
    recognizer = Counting()
    provider = Provider("Özet.")
    recorder = MeetingRecorder(recognizer, notes(tmp_path, provider), clock=lambda: STARTED)
    assert recorder.begin() and recorder.active
    assert not recorder.begin()
    block = (0.3 * np.sin(np.arange(512) / 5)).astype(np.float32)
    for _ in range(int(65 * SAMPLE_RATE / 512)):
        recorder.add(block)
    saved = recorder.finish()
    assert not recorder.active
    text = saved.path.read_text(encoding="utf-8")
    assert text.count("saniye") == recognizer.calls >= 3
    assert "[00:00:00]" in text and "Süre: 1 dk" in text
    with pytest.raises(NotRecording):
        recorder.finish()


def test_audio_is_not_taken_outside_a_recording(tmp_path):
    recognizer = Counting()
    recorder = MeetingRecorder(recognizer, notes(tmp_path, Provider()))
    recorder.add(np.ones(40 * SAMPLE_RATE, dtype=np.float32))
    assert recognizer.calls == 0 and recorder.abandon() is None


def test_switching_bilge_off_saves_what_was_transcribed_without_the_model(tmp_path):
    provider = Provider()
    recorder = MeetingRecorder(Counting(), notes(tmp_path, provider), clock=lambda: STARTED)
    recorder.begin()
    saved = recorder.abandon()
    assert saved is not None and provider.calls == []
    assert "Özet çıkarılamadı: kayıt, Bilge kapanınca yarıda kaldı" in saved.path.read_text(encoding="utf-8")


def test_a_piece_that_fails_is_marked_and_the_rest_still_counts():
    class Flaky:
        calls = 0

        def transcribe(self, samples):
            Flaky.calls += 1
            if Flaky.calls == 1:
                raise RuntimeError("model crashed")
            return "devam"

    blocks = [np.full(10 * SAMPLE_RATE, 0.2, dtype=np.float32)] * 7
    segments, seconds = transcribe_blocks(Flaky(), blocks, AssistantLanguage.TURKISH)
    assert seconds == 70
    assert segments[0].text == "(Bu bölüm yazıya dökülemedi.)" and segments[0].start == 0
    assert [segment.text for segment in segments[1:]] == ["devam"] * (len(segments) - 1)


def write_wav(path, seconds=1.5, rate=8000, channels=2):
    t = np.arange(int(seconds * rate)) / rate
    pcm = (np.sin(2 * np.pi * 440 * t) * 0.5 * 32767).astype("<i2")
    with wave.open(str(path), "wb") as out:
        out.setnchannels(channels)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(np.repeat(pcm, channels).tobytes())


def test_a_recording_is_decoded_to_sixteen_kilohertz_mono(tmp_path):
    path = tmp_path / "kayıt.wav"
    write_wav(path)
    blocks = list(audio_file.decode(path, block_seconds=0.5))
    audio = np.concatenate(blocks)
    assert len(blocks) > 1 and audio.dtype == np.float32 and audio.ndim == 1
    assert abs(len(audio) - 1.5 * SAMPLE_RATE) <= 64
    assert 0.4 < float(np.max(np.abs(audio))) <= 1.0


def test_a_file_that_is_not_audio_is_reported(tmp_path):
    path = tmp_path / "bozuk.mp3"
    path.write_bytes(b"not audio at all")
    with pytest.raises(audio_file.AudioFileError):
        list(audio_file.decode(path))
    assert audio_file.is_audio(path) and not audio_file.is_audio(tmp_path / "rapor.pdf")


def test_a_decoded_file_is_written_down_with_timestamps(tmp_path):
    path = tmp_path / "görüşme.wav"
    write_wav(path, seconds=2)
    segments, seconds = transcribe_blocks(Counting(), audio_file.decode(path), AssistantLanguage.TURKISH)
    assert abs(seconds - 2) < 0.01
    assert segments == [Segment(0.0, "2 saniye")]
