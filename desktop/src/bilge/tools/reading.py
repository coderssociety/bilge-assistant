"""The last long text Bilge read (a document, a web page, a news story), shared by the tools that read them so
"devamını oku" goes on with the next part instead of the start."""

import threading
from collections.abc import Callable
from datetime import datetime
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.core.tools import reading_continuation
from bilge.core.tools.reading_continuation import Part, Reading
from bilge.tools.base import Tool

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "tool": "Az önce okunan belgenin, web sayfasının ya da haberin devamını okur: 'devamını oku', 'devam et', "
        "'sonrası'.",
        "nothing": "Az önce okuduğum bir metin yok; neyi okumamı istersin?",
        "ended": "'{title}' metninin sonuna geldim; okunacak başka bir şey kalmadı.",
        "part": "{title}, bölüm {number}:\n{text}",
        "more": "(Devamı var.)",
        "last": "(Metnin sonu.)",
    },
    AssistantLanguage.ENGLISH: {
        "tool": "Reads on in the document, web page or news story just read: 'read on', 'continue', 'keep reading'.",
        "nothing": "I haven't read anything just now; what should I read?",
        "ended": "That's the end of '{title}'; there's nothing more to read.",
        "part": "{title}, part {number}:\n{text}",
        "more": "(There is more.)",
        "last": "(End of the text.)",
    },
}


class TextReading:
    def __init__(self, language: AssistantLanguage, clock: Callable[[], datetime] = datetime.now):
        self._texts = _TEXTS[language]
        self._clock = clock
        self._lock = threading.Lock()
        self._reading: Reading | None = None

    def start(self, title: str, text: str, size: int) -> str:
        """The first part of a new text, which is remembered for "devamını oku"."""
        with self._lock:
            part, self._reading = reading_continuation.first(title, text, size, self._clock())
        return self._told(part, first=True)

    def wants_more(self, command: str) -> bool:
        """The command goes on with the text just read."""
        with self._lock:
            recent = reading_continuation.is_recent(self._reading, self._clock())
        return recent and reading_continuation.asks_to_continue(command)

    def more(self) -> str:
        with self._lock:
            reading = self._reading
            if reading is None or not reading_continuation.is_recent(reading, self._clock()):
                return self._texts["nothing"]
            part, self._reading = reading_continuation.following(reading, self._clock())
        if not part.text:
            return self._texts["ended"].format(title=part.title)
        return self._told(part, first=False)

    def _told(self, part: Part, first: bool) -> str:
        """The first part reads as the tool always did; later ones say which part they are. Both say whether the
        text goes on, so the model can offer the rest."""
        texts = self._texts
        body = part.text if first else texts["part"].format(title=part.title, number=part.number, text=part.text)
        if part.has_more:
            return body + "\n" + texts["more"]
        return body if first else body + "\n" + texts["last"]


def continue_reading_tool(reading: TextReading, language: AssistantLanguage) -> Tool:
    return Tool(
        "continueReading",
        _TEXTS[language]["tool"],
        run=lambda _: reading.more(),
        # The text was written by whoever wrote the document, page or story.
        untrusted_output=True,
    )


def continued(reading: TextReading | None, arguments: dict[str, Any], command: str) -> dict[str, Any]:
    """A reading tool's refine: "devamını oku" asks for the next part, not the start again."""
    if reading is not None and reading.wants_more(command):
        return {**arguments, "continue": True}
    return {key: value for key, value in arguments.items() if key != "continue"}
