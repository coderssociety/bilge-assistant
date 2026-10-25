"""The browser in front and the shortcut that carries out a `browser_command` in it on Windows and Linux. Browsers
there don't tell other programs their tabs, so only what a shortcut can do is possible: no switching by tab title,
and numbers only up to 8 (Ctrl+9 is the last tab)."""

import re
from enum import StrEnum

from bilge.core.browser.browser_command import (
    Back,
    Bottom,
    BrowserCommand,
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
    Top,
)


class Family(StrEnum):
    CHROMIUM = "chromium"
    FIREFOX = "firefox"


MAX_TAB_NUMBER = 8
_CHROMIUM_WORDS = frozenset({"chrome", "chromium", "msedge", "brave", "vivaldi", "opera", "yandex"})
_FIREFOX_WORDS = frozenset({"firefox", "librewolf", "waterfox", "floorp"})
_SEPARATORS = re.compile(r"[.\-_ ]+")
_FIXED: dict[type, tuple[str, ...]] = {
    NextTab: ("ctrl", "tab"), PreviousTab: ("ctrl", "shift", "tab"), NewTab: ("ctrl", "t"), CloseTab: ("ctrl", "w"),
    ReopenTab: ("ctrl", "shift", "t"), Back: ("alt", "left"), Forward: ("alt", "right"), Reload: ("ctrl", "r"),
    ScrollDown: ("page_down",), ScrollUp: ("page_up",), Top: ("home",), Bottom: ("end",), Find: ("ctrl", "f"),
}  # fmt: skip


def family(program: str, app_class: str = "") -> Family | None:
    """From the front window's program ("msedge", "firefox-esr") and class or app id ("org.mozilla.firefox";
    Firefox's X11 window class is "Navigator")."""
    words = set(_SEPARATORS.split(program.lower())) | set(_SEPARATORS.split(app_class.lower()))
    if words & _FIREFOX_WORDS or app_class.lower() == "navigator":
        return Family.FIREFOX
    if words & _CHROMIUM_WORDS or {"microsoft", "edge"} <= words:
        return Family.CHROMIUM
    return None


def keys(command: BrowserCommand, browser: Family, linux: bool) -> tuple[str, ...] | None:
    """None when no shortcut does it (a tab by title, a tab number above 8)."""
    fixed = _FIXED.get(type(command))
    if fixed is not None:
        return fixed
    # Firefox on Linux picks tabs with Alt+number; Ctrl+number does it everywhere else.
    modifier = "alt" if linux and browser is Family.FIREFOX else "ctrl"
    if isinstance(command, LastTab):
        return modifier, "9"
    if isinstance(command, Tab) and 1 <= command.index <= MAX_TAB_NUMBER:
        return modifier, str(command.index)
    return None
