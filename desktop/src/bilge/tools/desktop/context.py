"""'Bunu özetle', 'bunu çevir', 'şunu açıkla', 'seçili dosyayı aç': what "bu" points at is the selected text, else
the text on the clipboard, else the files picked in the file manager (Explorer's selection, or on Linux the files
copied there), else what the front window shows. Whatever is read may have been written by anyone, so it is
untrusted: the model only summarizes, translates or explains it."""

import logging
from collections.abc import Callable
from pathlib import Path
from typing import Any

from bilge.core import ocr_text
from bilge.core.context import context_intent, screen_context
from bilge.core.context.context_intent import Action, Kind
from bilge.core.context.screen_context import ContextItem, Files, ScreenContext, Text
from bilge.core.language import AssistantLanguage
from bilge.desktop.base import Clipboard, FileSelection, Opener, ScreenshotArea, ScreenText
from bilge.desktop.process import DesktopError
from bilge.tools import documents
from bilge.tools.base import Tool, ToolError
from bilge.tools.desktop.common import failure, obj, string_argument, text
from bilge.tools.desktop.files import is_executable
from bilge.tools.desktop.screen import read_text
from bilge.tools.reading import TextReading, continued

log = logging.getLogger(__name__)

CONTEXT_CHARACTERS = 6000
MAX_OPENED_FILES = 5

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "tool": "Kullanıcının 'bu', 'şu' diye gösterdiği şeyi özetler, çevirir, açıklar, okur ya da açar ('bunu "
        "özetle', 'bunu İngilizceye çevir', 'şunu açıkla', 'seçili dosyayı aç'): seçili metin, yoksa panodaki "
        "metin, yoksa dosya yöneticisinde seçili dosya, yoksa öndeki pencerede yazanlar. 'Bunu Ahmet'e gönder' "
        "için sendEmail kullan.",
        "command": "Kullanıcının isteği, olduğu gibi",
        "unclear": "Bununla ne yapmamı istediğini anlayamadım; 'bunu özetle' ya da 'bunu çevir' diyebilirsin.",
        "nothing": "Neyi kastettiğini bulamadım. Bir metni seç ya da kopyala, ya da dosyayı dosya yöneticisinde seç.",
        "selected": "Seçili metin",
        "copied": "Panodaki metin",
        "screen": "Öndeki penceredeki yazı",
        "document": "Belge: {name}",
        "material": "{label}:\n{text}",
        "no_document": "Seçili dosyalardan okuyabileceğim bir belge yok.",
        "unreadable": "'{name}' dosyasını okuyamadım.",
        "empty": "'{name}' içinde okunabilir yazı yok.",
        "not_openable": "Seçili metin açılacak bir şey değil; bir dosyayı seçip 'şunu aç' diyebilirsin.",
        "program": "Güvenlik için '{name}' gibi programları sesle açmıyorum.",
        "opened": "{name} açılıyor.",
        "opened_many": "{count} dosya açılıyor.",
        "read_failed": "Seçili olanı okuyamadım.",
    },
    AssistantLanguage.ENGLISH: {
        "tool": "Summarizes, translates, explains, reads or opens what the user points at with 'this' or 'that' "
        "('summarize this', 'translate this into Turkish', 'explain that', 'open the selected file'): the selected "
        "text, else the clipboard's text, else the file selected in the file manager, else the text in the front "
        "window. For 'send this to Anna' use sendEmail.",
        "command": "The user's request, as said",
        "unclear": "I didn't get what to do with it; you could say 'summarize this' or 'translate this'.",
        "nothing": "I couldn't find what you mean. Select or copy some text, or select the file in the file manager.",
        "selected": "Selected text",
        "copied": "Text on the clipboard",
        "screen": "Text in the front window",
        "document": "Document: {name}",
        "material": "{label}:\n{text}",
        "no_document": "None of the selected files is a document I can read.",
        "unreadable": "I couldn't read '{name}'.",
        "empty": "'{name}' has no readable text.",
        "not_openable": "Selected text isn't something to open; select a file and say 'open this'.",
        "program": "For safety I don't open programs like '{name}' by voice.",
        "opened": "Opening {name}.",
        "opened_many": "Opening {count} files.",
        "read_failed": "I couldn't read what is selected.",
    },
}


class ContextReader:
    """Reads only as far as it needs, in the order "bu" is resolved."""

    def __init__(self, clipboard: Clipboard, files: FileSelection):
        self._clipboard = clipboard
        self._files = files

    def item(self, wanted: Kind | None) -> ContextItem | None:
        return screen_context.resolve(wanted, self.snapshot(wanted))

    def snapshot(self, wanted: Kind | None) -> ScreenContext:
        if wanted in (None, Kind.TEXT):
            selected = _read(self._clipboard.selection)
            if selected.strip():
                return ScreenContext(selected_text=selected)
            copied = _read(self._clipboard.read)
            if copied.strip() and not screen_context.names_files(copied):
                return ScreenContext(clipboard_text=copied)
        if wanted in (Kind.TEXT, Kind.PAGE):
            return ScreenContext()
        try:
            files = self._files.selected()
        except DesktopError:
            log.info("Could not read the file selection", exc_info=True)
            files = ()
        return ScreenContext(selected_files=tuple(str(path) for path in files))


def _read(source: Callable[[], str]) -> str:
    """A selection that can't be read (a console in front on Windows) counts as none, so the next source is tried."""
    try:
        return source()
    except DesktopError:
        log.info("Could not read the selection or the clipboard", exc_info=True)
        return ""


def context_tool(
    reader: ContextReader,
    screen: ScreenText,
    opener: Opener,
    language: AssistantLanguage,
    reading: TextReading | None = None,
) -> Tool:
    texts = _TEXTS[language]

    def run(arguments: dict[str, Any]) -> str:
        if arguments.get("continue") and reading is not None:
            return reading.more()
        intent = context_intent.parse(string_argument(arguments, "command"), language)
        if intent is None:
            raise ToolError(texts["unclear"])
        if intent.action is Action.OPEN:
            return open_item(reader.item(intent.wanted or Kind.FILE))
        item = reader.item(intent.wanted)
        if isinstance(item, Text):
            return material(texts["copied" if item.copied else "selected"], item.text)
        if isinstance(item, Files):
            return document(item)
        if intent.wanted in (Kind.TEXT, Kind.FILE):
            raise ToolError(texts["nothing"])
        # No browser here says which page it shows, so "bu sayfa" is what the front window shows.
        shown = ocr_text.cleaned(read_text(screen, ScreenshotArea.FRONT_WINDOW, language))
        if not shown:
            raise ToolError(texts["nothing"])
        return material(texts["screen"], shown)

    def material(label: str, content: str) -> str:
        if reading is not None:
            content = reading.start(label, content, CONTEXT_CHARACTERS)
        else:
            content = content[:CONTEXT_CHARACTERS]
        return texts["material"].format(label=label, text=content)

    def document(item: Files) -> str:
        readable = next((Path(url) for url in item.urls if _readable(url)), None)
        if readable is None:
            raise ToolError(texts["no_document"])
        try:
            content = documents.text_of(readable).strip()
        except documents.UnreadableDocument as error:
            raise ToolError(texts["unreadable"].format(name=readable.name)) from error
        if not content:
            raise ToolError(texts["empty"].format(name=readable.name))
        return material(texts["document"].format(name=readable.name), content)

    def open_item(item: ContextItem | None) -> str:
        if isinstance(item, Text):
            raise ToolError(texts["not_openable"])
        if not isinstance(item, Files):
            raise ToolError(texts["nothing"])
        paths = [Path(url) for url in item.urls[:MAX_OPENED_FILES]]
        program = next((path for path in paths if is_executable(path)), None)
        if program is not None:
            raise ToolError(texts["program"].format(name=program.name))
        try:
            for path in paths:
                opener.open(str(path))
        except DesktopError as error:
            raise failure(error, language) from error
        if len(paths) == 1:
            return texts["opened"].format(name=paths[0].name)
        return texts["opened_many"].format(count=len(paths))

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        said = {**arguments, "command": command} if context_intent.parse(command, language) else arguments
        return continued(reading, said, command)

    return Tool(
        "useContext",
        texts["tool"],
        run=run,
        parameters=obj(["command"], command=text(texts["command"])),
        untrusted_output=True,
        refine=refine,
    )


def _readable(url: str) -> bool:
    return Path(url).suffix.lower().lstrip(".") in documents.READABLE
