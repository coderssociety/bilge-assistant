"""Browser control by voice ("sonraki sekmeye geç", "geri git", "aşağı kaydır", "bu sayfada fiyatı ara") through the
browser's own shortcuts. Keys are sent only when a browser is the window in front, so "sekmeyi kapat" can never close
another app's window; where the desktop doesn't say which window that is (GNOME on Wayland), nothing is sent."""

import sys
import time
from collections.abc import Callable
from typing import Any

from bilge.core.browser import browser_command, browser_keys
from bilge.core.browser.browser_command import (
    Back,
    Bottom,
    CloseTab,
    Find,
    Forward,
    LastTab,
    NewTab,
    NextTab,
    PreviousTab,
    Reload,
    ReopenTab,
    ScrollDown,
    ScrollUp,
    Tab,
    TabNamed,
    Top,
)
from bilge.core.language import AssistantLanguage
from bilge.core.tools import typed_text
from bilge.desktop.base import Keyboard
from bilge.desktop.process import DesktopError
from bilge.tools.base import Tool, ToolError
from bilge.tools.desktop.common import failure, obj, string_argument, text
from bilge.tools.desktop.typing import front_window

# The find bar takes a moment to open and take the typing.
FIND_FIELD_SECONDS = 0.25

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "tool": "Öndeki tarayıcıda sekmeler arasında geçer (sonraki, önceki, 1-8. ya da son sekme), sekme açar, kapatır "
        "ve kapatılanı geri açar, geri ve ileri gider, sayfayı yeniler, kaydırır ve sayfada arama yapar.",
        "command": "Kullanıcının isteği, olduğu gibi",
        "unclear": "Tarayıcıda ne yapmamı istediğini anlayamadım.",
        "unknown_front": "Öndeki pencerenin hangisi olduğunu bu masaüstünde göremiyorum; tuşlar başka bir uygulamaya "
        "gitmesin diye tarayıcı komutlarını çalıştırmıyorum.",
        "no_browser": "Önde bir tarayıcı yok; önce tarayıcı penceresini öne getir.",
        "by_title": "Sekmelere adıyla geçemiyorum; tarayıcı sekme adlarını diğer programlara göstermiyor. 'Sonraki "
        "sekme', 'üçüncü sekmeye geç' ya da 'son sekme' diyebilirsin.",
        "by_number": "Sekmelere numarayla yalnızca 1'den 8'e kadar geçebiliyorum; 'son sekme' de diyebilirsin.",
        "failed": "Tarayıcıya tuşları gönderemedim.",
        "next": "Sonraki sekme.",
        "previous": "Önceki sekme.",
        "new": "Yeni sekme açtım.",
        "close": "Sekmeyi kapattım.",
        "reopen": "Kapattığın sekmeyi geri açtım.",
        "tab": "{number}. sekme.",
        "last": "Son sekme.",
        "back": "Geri gittim.",
        "forward": "İleri gittim.",
        "reload": "Sayfayı yeniledim.",
        "down": "Aşağı kaydırdım.",
        "up": "Yukarı kaydırdım.",
        "top": "Başına çıktım.",
        "bottom": "Sonuna indim.",
        "find": "Sayfada '{query}' arıyorum.",
    },
    AssistantLanguage.ENGLISH: {
        "tool": "In the browser in front: switches tabs (next, previous, tab 1-8 or the last one), opens and closes a "
        "tab and reopens a closed one, goes back and forward, reloads, scrolls and finds text on the page.",
        "command": "The user's request, as said",
        "unclear": "I didn't get what to do in the browser.",
        "unknown_front": "This desktop doesn't tell me which window is in front, so I don't send browser keys that "
        "could reach another app.",
        "no_browser": "There's no browser in front; bring the browser window forward first.",
        "by_title": "I can't switch to a tab by its title; the browser doesn't show tab titles to other programs. You "
        "can say 'next tab', 'switch to the third tab' or 'last tab'.",
        "by_number": "I can only switch to tabs 1 to 8 by number; you can also say 'last tab'.",
        "failed": "I couldn't send the keys to the browser.",
        "next": "Next tab.",
        "previous": "Previous tab.",
        "new": "Opened a new tab.",
        "close": "Closed the tab.",
        "reopen": "Reopened the tab you closed.",
        "tab": "Tab {number}.",
        "last": "Last tab.",
        "back": "Went back.",
        "forward": "Went forward.",
        "reload": "Reloaded the page.",
        "down": "Scrolled down.",
        "up": "Scrolled up.",
        "top": "At the top.",
        "bottom": "At the bottom.",
        "find": "Looking for '{query}' on the page.",
    },
}
_REPLIES: dict[type, str] = {
    NextTab: "next", PreviousTab: "previous", NewTab: "new", CloseTab: "close", ReopenTab: "reopen", LastTab: "last",
    Back: "back", Forward: "forward", Reload: "reload", ScrollDown: "down", ScrollUp: "up", Top: "top",
    Bottom: "bottom",
}  # fmt: skip


def browser_tool(
    keyboard: Keyboard,
    language: AssistantLanguage,
    linux: bool | None = None,
    pause: Callable[[float], None] = time.sleep,
) -> Tool:
    texts = _TEXTS[language]
    on_linux = sys.platform.startswith("linux") if linux is None else linux

    def run(arguments: dict[str, Any]) -> str:
        command = browser_command.parse(string_argument(arguments, "command"), language)
        if command is None:
            raise ToolError(texts["unclear"])
        if isinstance(command, TabNamed):
            raise ToolError(texts["by_title"])
        window = front_window(keyboard)
        if window is None:
            raise ToolError(texts["unknown_front"])
        browser = browser_keys.family(window.name, window.app_class)
        if browser is None:
            raise ToolError(texts["no_browser"])
        keys = browser_keys.keys(command, browser, on_linux)
        if keys is None:
            raise ToolError(texts["by_number"])
        try:
            keyboard.press(*keys)
            if isinstance(command, Find):
                return find(command.query)
        except DesktopError as error:
            raise failure(error, language, texts["failed"]) from error
        if isinstance(command, Tab):
            return texts["tab"].format(number=command.index)
        return texts[_REPLIES[type(command)]]

    def find(query: str) -> str:
        pause(FIND_FIELD_SECONDS)
        keyboard.type(typed_text.sanitized(query))
        keyboard.press("return")
        return texts["find"].format(query=query)

    return Tool(
        "browserControl",
        texts["tool"],
        run=run,
        parameters=obj(["command"], command=text(texts["command"])),
        # The model may reword the request; the parser reads the words as said.
        refine=lambda arguments, said: {**arguments, "command": said} if claims(said, language) else arguments,
    )


def claims(command: str, language: AssistantLanguage) -> bool:
    return browser_command.parse(command, language) is not None
