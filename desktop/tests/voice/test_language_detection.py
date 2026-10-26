import numpy as np
import pytest

from bilge.voice.idle import IdleUnloadingRecognizer
from bilge.voice.recognizers import Detected, GuardedRecognizer, RecognitionError, detects_language

SAMPLE_RATE = 16_000


def speech(seconds: float = 1.0) -> np.ndarray:
    """Quiet background with a louder stretch in the middle, as the loudness guard expects of speech."""
    rng = np.random.default_rng(0)
    audio = rng.normal(0, 0.001, int(seconds * SAMPLE_RATE)).astype(np.float32)
    middle = slice(len(audio) // 4, 3 * len(audio) // 4)
    t = np.arange(middle.stop - middle.start) / SAMPLE_RATE
    audio[middle] += (0.3 * np.sin(2 * np.pi * 200 * t)).astype(np.float32)
    return audio


class Detecting:
    def __init__(self, text="Guten Morgen", language="de"):
        self.text, self.language = text, language
        self.asked = []

    def transcribe(self, samples):
        return self.text

    def transcribe_detecting(self, samples, languages):
        self.asked.append(tuple(languages))
        return Detected(self.text, self.language)


class Plain:
    def transcribe(self, samples):
        return "merhaba"


def test_only_recognizers_that_tell_languages_apart_count():
    assert detects_language(Detecting())
    assert not detects_language(Plain())
    assert detects_language(GuardedRecognizer(Detecting()))
    assert not detects_language(GuardedRecognizer(Plain()))


def test_the_guard_passes_the_choice_of_languages_on():
    inner = Detecting()
    detected = GuardedRecognizer(inner).transcribe_detecting(speech(), ("tr", "de"))
    assert detected == Detected("Guten Morgen", "de")
    assert inner.asked == [("tr", "de")]


def test_the_guard_does_not_send_silence():
    inner = Detecting()
    detected = GuardedRecognizer(inner).transcribe_detecting(np.zeros(SAMPLE_RATE, dtype=np.float32), ("tr", "en"))
    assert detected.text == "" and inner.asked == []


def test_the_guard_refuses_when_the_recognizer_cannot_detect():
    with pytest.raises(RecognitionError):
        GuardedRecognizer(Plain()).transcribe_detecting(speech(), ("tr", "en"))


def test_a_model_let_go_while_idle_still_detects_once_loaded_again():
    recognizer = IdleUnloadingRecognizer(Detecting, idle_seconds=600, check_seconds=3600)
    assert recognizer.detects_language
    assert recognizer.transcribe_detecting(speech(), ("tr", "de")).language == "de"
    recognizer.close()
    plain = IdleUnloadingRecognizer(Plain, idle_seconds=600, check_seconds=3600)
    assert not plain.detects_language
    with pytest.raises(RecognitionError):
        plain.transcribe_detecting(speech(), ("tr", "en"))
    plain.close()


def test_faster_whisper_transcribes_in_the_likelier_of_the_two_languages():
    from types import SimpleNamespace

    from bilge.voice.recognizers import WhisperRecognizer

    class Model:
        def __init__(self):
            self.languages = []

        def detect_language(self, audio):
            return "az", 0.5, [("az", 0.5), ("en", 0.2), ("tr", 0.3)]

        def transcribe(self, audio, language=None, **_):
            self.languages.append(language)
            return iter([SimpleNamespace(text=" Günaydın "), SimpleNamespace(text="nasılsın?")]), None

    recognizer = WhisperRecognizer.__new__(WhisperRecognizer)
    recognizer._model = Model()
    detected = recognizer.transcribe_detecting(speech(), ("en", "tr"))
    assert detected == Detected("Günaydın nasılsın?", "tr")
    assert recognizer._model.languages == ["tr"]
