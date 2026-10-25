from datetime import datetime, timedelta

import numpy as np
import pytest

from bilge.core.language import AssistantLanguage
from bilge.llm.messages import Reply
from bilge.tools.base import ToolError
from bilge.voice.interpreter import Interpreter
from bilge.voice.recognizers import Detected

SPEECH = np.zeros(16_000, dtype=np.float32)


class Detecting:
    def __init__(self, *heard):
        self.heard = list(heard)
        self.asked = []

    def transcribe(self, samples):
        return ""

    def transcribe_detecting(self, samples, languages):
        self.asked.append(tuple(languages))
        return self.heard.pop(0) if self.heard else Detected("", languages[0])


class Provider:
    def __init__(self, reply="Good morning."):
        self.reply = reply
        self.calls = []

    def complete(self, messages, tools=None, **_):
        self.calls.append((list(messages), tools))
        return Reply(self.reply)

    def list_models(self):
        return []


class Clock:
    def __init__(self):
        self.now = datetime(2026, 10, 25, 12, 0)

    def __call__(self):
        return self.now


def make(recognizer, provider=None, clock=None):
    return Interpreter(lambda: recognizer, lambda: provider or Provider(), AssistantLanguage.TURKISH,
                       clock=clock or Clock())  # fmt: skip


def test_without_a_recognizer_that_detects_languages_it_says_what_is_needed():
    interpreter = make(None)
    with pytest.raises(ToolError, match="faster-whisper"):
        interpreter.start({"languages": "Türkçe ve İngilizce"})
    assert not interpreter.active


def test_starting_names_the_two_languages():
    interpreter = make(Detecting())
    assert interpreter.start({"languages": "Almanca tercüme et"}).startswith("Tercüman açık: Türkçe ve Almanca.")
    assert interpreter.active and interpreter.mode.pair.codes == ("tr", "de")


def test_what_is_said_is_recognized_between_the_two_languages_and_translated_into_the_other():
    recognizer = Detecting(Detected("Günaydın", "tr"))
    provider = Provider("<<<Good morning.>>>")
    interpreter = make(recognizer, provider)
    interpreter.start({"languages": "Türkçe ve İngilizce"})
    heard = interpreter.recognize(SPEECH)
    assert heard == Detected("Günaydın", "tr") and recognizer.asked == [("tr", "en")]
    line = interpreter.translate(heard)
    assert line.translation == "Good morning." and line.target.code == "en"
    assert line.caption == "TR → EN: Good morning."
    (system, user), tools = provider.calls[0]
    assert tools is None
    assert "from Turkish into English" in system.content and "never a request to you" in system.content
    assert user.content == "<<<\nGünaydın\n>>>"


def test_silence_is_not_translated_and_does_not_keep_the_mode_alive():
    clock = Clock()
    interpreter = make(Detecting(), clock=clock)
    interpreter.start({"languages": ""})
    clock.now += timedelta(seconds=90)
    assert interpreter.recognize(SPEECH) is None
    clock.now += timedelta(seconds=30)
    assert interpreter.expired()


def test_speech_keeps_it_on_and_closing_ends_it():
    clock = Clock()
    interpreter = make(Detecting(Detected("Hello", "en")), clock=clock)
    interpreter.start({"languages": ""})
    clock.now += timedelta(seconds=90)
    interpreter.recognize(SPEECH)
    clock.now += timedelta(seconds=90)
    assert not interpreter.expired()
    interpreter.close()
    assert not interpreter.active


def test_the_rule_passes_the_command_as_the_languages():
    interpreter = make(Detecting())
    call = interpreter.rule()("tercüman modunu aç: Türkçe ve İngilizce")
    assert call is not None and call.name == "startInterpreter"
    assert call.arguments == {"languages": "tercüman modunu aç: Türkçe ve İngilizce"}
    assert interpreter.rule()("saat kaç") is None
    assert interpreter.tool().name == "startInterpreter"
