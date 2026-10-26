"""Interpreter mode: what either person says is recognized in whichever of the two languages it was said in,
translated by the model into the other one and spoken in that language.

The speech is only ever translated: it never reaches the agent or its tools, and the model is told it is data.
Recognition needs a recognizer that can tell the two languages apart (faster-whisper); where the configured one
can't, a local faster-whisper model is used for the mode if it has been downloaded.
"""

from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from typing import Any

import numpy as np

from bilge.brain.routing import Rule, rule
from bilge.core.interpreter import interpreter_command
from bilge.core.interpreter.interpretation import InterpreterMode, caption, cleaned, instructions, request
from bilge.core.language import AssistantLanguage
from bilge.core.translation_request import SpeechLanguage
from bilge.llm.messages import Message
from bilge.llm.providers import ChatProvider
from bilge.tools.base import Tool, ToolError
from bilge.tools.desktop.common import obj, string_argument, text
from bilge.voice.recognizers import Detected, Recognizer

TRANSLATION_TOKENS = 600

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "tool": "Tercüman modunu açar: iki dilde söylenenleri birinden ötekine çevirip o dilde seslendirir.",
        "languages": "Çevrilecek iki dil, söylendiği gibi: 'Türkçe ve Almanca'",
        "started": "Tercüman açık: {pair}. Söyleneni öteki dile çevirip söyleyeceğim. Kapatmak için 'tercümanı "
        "kapat' de.",
        "needs_model": "Tercüman modu için konuşulan dili ayırt edebilen yerel Whisper modeli (faster-whisper) "
        "gerekiyor. Ayarlar → Tanıma'da yerel tanımayı işlemci ya da NVIDIA ekran kartı ile seçip modeli indir.",
        "stopped": "Tercümanı kapattım.",
        "timed_out": "İki dakikadır konuşma olmadı, tercümanı kapattım.",
        "failed": "Bunu çeviremedim.",
    },
    AssistantLanguage.ENGLISH: {
        "tool": "Starts interpreter mode: what is said in either of two languages is translated into the other and "
        "spoken in it.",
        "languages": "The two languages, as said: 'English and German'",
        "started": "Interpreter on: {pair}. I'll say what's said in the other language. Say 'stop interpreting' to "
        "end it.",
        "needs_model": "Interpreter mode needs a local Whisper model that can tell languages apart (faster-whisper). "
        "Choose local recognition on the processor or an NVIDIA card under Settings → Recognition and download "
        "the model.",
        "stopped": "Interpreter off.",
        "timed_out": "Nobody has spoken for two minutes, so I turned the interpreter off.",
        "failed": "I couldn't translate that.",
    },
}


@dataclass(frozen=True)
class Line:
    source: SpeechLanguage
    target: SpeechLanguage
    said: str
    translation: str

    @property
    def caption(self) -> str:
        return caption(self.source, self.target, self.translation)


class Interpreter:
    def __init__(
        self,
        recognizer: Callable[[], Recognizer | None],
        provider: Callable[[], ChatProvider],
        language: AssistantLanguage,
        clock: Callable[[], datetime] = datetime.now,
    ):
        """`recognizer` finds one that tells languages apart, or None; it is asked for when the mode starts."""
        self._find_recognizer = recognizer
        self._provider = provider
        self.language = language
        self.texts = _TEXTS[language]
        self._clock = clock
        self._recognizer: Recognizer | None = None
        self.mode = InterpreterMode()

    @property
    def active(self) -> bool:
        return self.mode.active

    def start(self, arguments: dict[str, Any]) -> str:
        pair = interpreter_command.language_pair(string_argument(arguments, "languages"), self.language)
        if self._recognizer is None:
            self._recognizer = self._find_recognizer()
        if self._recognizer is None:
            raise ToolError(self.texts["needs_model"])
        self.mode.start(pair, self._clock())
        return self.texts["started"].format(pair=pair.spoken(self.language))

    def recognize(self, samples: np.ndarray) -> Detected | None:
        """What was said and in which of the two languages; None for nothing worth translating."""
        pair, recognizer = self.mode.pair, self._recognizer
        if pair is None or recognizer is None:
            return None
        detected = recognizer.transcribe_detecting(samples, pair.codes)  # type: ignore[attr-defined]
        if not detected.text.strip():
            return None
        self.mode.heard(self._clock())
        return detected

    def is_stop(self, said: str) -> bool:
        return interpreter_command.is_stop(said)

    def translate(self, heard: Detected) -> Line:
        """Raises ProviderError when the model can't be reached."""
        pair = self.mode.pair or interpreter_command.language_pair("", self.language)
        source, target = pair.get(heard.language), pair.other(heard.language)
        messages = [Message.system(instructions(source, target)), Message.user(request(heard.text))]
        reply = self._provider().complete(messages, None, temperature=0.2, max_tokens=TRANSLATION_TOKENS)
        return Line(source, target, heard.text, cleaned(reply.text))

    def expired(self) -> bool:
        return self.mode.expired(self._clock())

    def stop(self) -> None:
        """The mode ends, and a model loaded just for it (faster-whisper turbo, ~1.5 GB) is let go rather than kept
        for the rest of the session; the main recognizer stays with Bilge."""
        self.mode.stop()
        self._recognizer = None

    def close(self) -> None:
        """Bilge stops listening."""
        self.stop()

    def tool(self) -> Tool:
        return Tool("startInterpreter", self.texts["tool"], run=self.start,
                    parameters=obj(languages=text(self.texts["languages"])))  # fmt: skip

    def rule(self) -> Rule:
        return rule("startInterpreter", interpreter_command.is_start, lambda command: {"languages": command})
