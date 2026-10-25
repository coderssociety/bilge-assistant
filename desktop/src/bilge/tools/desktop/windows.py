"""The window in front: minimize, maximize, restore, full screen, close."""

from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.desktop.base import WindowAction, WindowControl
from bilge.desktop.process import DesktopError, NotPossibleHere
from bilge.tools.base import Risk, Tool, ToolError
from bilge.tools.desktop.common import choice, failure, obj, string_argument

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "window": "Öndeki pencereyi küçültür, büyütür, eski boyutuna getirir, tam ekran yapar ya da tam ekrandan çıkarır, ya da kapatır.",
        "close_question": "Öndeki pencere kapatılsın mı? Kaydedilmemiş değişiklikler kaybolabilir.",
        "unsupported_gnome": "GNOME'un Wayland oturumu, uygulamaların başka pencereleri yönetmesine izin vermiyor. Klavyeyle yapabilirsin: Süper+H küçültür, Süper+Yukarı ok büyütür, Süper+Aşağı ok eski boyutuna getirir, Alt+F4 kapatır.",
        "unsupported": "Bu masaüstü, uygulamaların başka pencereleri yönetmesine izin vermiyor.",
        "failed": "Öndeki pencereyi değiştiremedim.",
        WindowAction.MINIMIZE: "Pencereyi küçülttüm.",
        WindowAction.MAXIMIZE: "Pencereyi büyüttüm.",
        WindowAction.RESTORE: "Pencereyi eski boyutuna getirdim.",
        WindowAction.FULL_SCREEN: "Pencerenin tam ekran durumunu değiştirdim.",
        WindowAction.CLOSE: "Pencereyi kapattım.",
    },
    AssistantLanguage.ENGLISH: {
        "window": "Minimizes, maximizes, restores, toggles full screen for, or closes the window in front.",
        "close_question": "Close the window in front? Unsaved changes may be lost.",
        "unsupported_gnome": "GNOME's Wayland session doesn't let apps manage other windows. The keyboard can: Super+H minimizes, Super+Up maximizes, Super+Down restores, Alt+F4 closes.",
        "unsupported": "This desktop doesn't let apps manage other windows.",
        "failed": "I couldn't change the window in front.",
        WindowAction.MINIMIZE: "I minimized the window.",
        WindowAction.MAXIMIZE: "I maximized the window.",
        WindowAction.RESTORE: "I restored the window to its size.",
        WindowAction.FULL_SCREEN: "I toggled full screen for the window.",
        WindowAction.CLOSE: "I closed the window.",
    },
}  # fmt: skip


def window_tool(windows: WindowControl, language: AssistantLanguage) -> Tool:
    texts = _TEXTS[language]

    def run(arguments: dict[str, Any]) -> str:
        try:
            action = WindowAction(string_argument(arguments, "action"))
        except ValueError as error:
            raise ToolError(texts["failed"]) from error
        try:
            windows.act(action)
        except NotPossibleHere as error:
            raise ToolError(texts["unsupported_gnome" if error.desktop == "gnome" else "unsupported"]) from error
        except DesktopError as error:
            raise failure(error, language, texts["failed"]) from error
        return texts[action]

    def question(arguments: dict[str, Any]) -> str | None:
        return texts["close_question"] if string_argument(arguments, "action") == WindowAction.CLOSE else None

    return Tool("windowControl", texts["window"], run=run, parameters=obj(["action"], action=choice(WindowAction, "")),
                risk=Risk.CONFIRM, confirmation=question)  # fmt: skip
