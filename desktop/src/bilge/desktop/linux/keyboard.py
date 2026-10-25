"""Typing into the app in front, and finding out which app that is.

X11 lets any program do both (xdotool). Wayland deliberately doesn't: wtype works on compositors with the virtual
keyboard protocol (Sway, Hyprland and other wlroots ones; not GNOME or KDE), ydotool works everywhere through the
kernel but types by key position, so text outside US ASCII is pasted instead. When wtype is refused, ydotool is
tried next. Which window is in front can be asked of Sway, Hyprland and KDE (kdotool); GNOME on Wayland doesn't say.
"""

import json
import re
import time
from collections.abc import Callable
from pathlib import Path

from bilge.desktop.base import FrontWindow
from bilge.desktop.linux.environment import Environment
from bilge.desktop.process import DesktopError, MissingProgram, Runner

_KEY_DELAY_MS = 8
# Linux input event codes, for ydotool.
_LEFT_SHIFT, _LEFT_CTRL, _ENTER, _BACKSPACE, _V = 42, 29, 28, 14, 47
# A shortcut as (event code for ydotool 1.x, key name for ydotool 0.1.8, which Ubuntu 22.04 and Debian 12 ship).
_PASTE = ((_LEFT_CTRL, "ctrl"), (_V, "v"))
_NEW_LINE = ((_LEFT_SHIFT, "shift"), (_ENTER, "enter"))
_PASTE_SETTLE_SECONDS = 0.3
# WM_CLASS(STRING) = "gnome-terminal-server", "Gnome-terminal": the first is the instance, closest to the program.
_WM_CLASS = re.compile(r'WM_CLASS\(\w+\) = "([^"]*)"')


class LinuxKeyboard:
    def __init__(self, runner: Runner, environment: Environment, clipboard=None):
        self._runner = runner
        self._environment = environment
        self._clipboard = clipboard
        self._legacy_ydotool: bool | None = None

    def _typists(self) -> list[str]:
        env = self._environment
        # GNOME and KWin don't offer wtype's protocol to ordinary programs, so it would fail every time there.
        wayland_order = ["ydotool"] if env.gnome or env.kde else ["wtype", "ydotool"]
        order = wayland_order if env.wayland else ["xdotool"]
        installed = [program for program in order if self._runner.has(program)]
        if not installed:
            raise MissingProgram(*order)
        return installed

    def _with_typist(self, action: Callable[[str], None]) -> None:
        """wtype fails at once, before typing anything, where its protocol is missing; ydotool is tried then."""
        failure: DesktopError | None = None
        for typist in self._typists():
            try:
                action(typist)
                return
            except MissingProgram:
                raise
            except DesktopError as error:
                failure = error
        assert failure is not None
        raise failure

    def _is_legacy_ydotool(self) -> bool:
        """ydotool 0.1.8 takes key names and --key-delay; 1.x takes event codes and -d. 0.1.8's help offers
        "--delay", 1.x's "--key-hold" and "--next-delay"; anything else is taken for 1.x."""
        if self._legacy_ydotool is None:
            done = self._runner.run(["ydotool", "type", "--help"], timeout=5)
            usage = done.stdout + done.stderr
            self._legacy_ydotool = "--delay" in usage and "--key-hold" not in usage
        return self._legacy_ydotool

    def front_window(self) -> FrontWindow | None:
        env = self._environment
        try:
            if env.sway and self._runner.has("swaymsg"):
                return _sway_focused(json.loads(self._runner.check(["swaymsg", "-t", "get_tree"])))
            if env.hyprland and self._runner.has("hyprctl"):
                window = json.loads(self._runner.check(["hyprctl", "activewindow", "-j"]))
                app_class = str(window.get("class", "")).lower()
                pid = window.get("pid")
                program = _program_name(pid) if isinstance(pid, int) else None
                return FrontWindow(program or app_class, str(window.get("title", "")), app_class)
            if env.kde and env.wayland and self._runner.has("kdotool"):
                return self._xdotool_style("kdotool")
            if not env.wayland and self._runner.has("xdotool"):
                return self._xdotool_style("xdotool")
        except (DesktopError, ValueError) as error:
            raise DesktopError(f"Could not read the front window: {error}") from error
        return None

    def _xdotool_style(self, program: str) -> FrontWindow | None:
        window = self._runner.run([program, "getactivewindow"])
        if not window.ok or not window.stdout.strip():
            return None
        window_id = window.stdout.split()[0]
        app_class = self._window_class(program, window_id)
        pid = self._runner.run([program, "getwindowpid", window_id]).stdout.strip()
        name = (_program_name(int(pid)) if pid.isdigit() else None) or app_class
        title = self._runner.run([program, "getwindowname", window_id]).stdout.strip()
        return FrontWindow(name, title, app_class) if name else None

    def _window_class(self, program: str, window_id: str) -> str:
        """xprop on X11: the xdotool many distributions ship (3.2016) has no getwindowclassname."""
        if program == "xdotool" and self._runner.has("xprop"):
            found = _WM_CLASS.search(self._runner.run(["xprop", "-id", window_id, "WM_CLASS"]).stdout)
            if found:
                return found.group(1).lower()
        done = self._runner.run([program, "getwindowclassname", window_id])
        return done.stdout.strip().lower() if done.ok else ""

    def type(self, text: str) -> None:
        """The text goes in on standard input, which keeps what the user dictates out of the process list."""
        self._with_typist(lambda typist: self._type_with(typist, text))

    def _type_with(self, typist: str, text: str) -> None:
        delay = str(_KEY_DELAY_MS)
        if typist == "xdotool" and not _has_foreign_capital(text):
            self._runner.check(["xdotool", "type", "--clearmodifiers", "--delay", delay, "--file", "-"], input=text)
        elif typist == "wtype":
            self._runner.check(["wtype", "-d", delay, "-"], input=text)
        elif typist == "ydotool" and text.isascii():
            delay_option = "--key-delay" if self._is_legacy_ydotool() else "-d"
            self._runner.check(["ydotool", "type", delay_option, delay, "--file", "-"], input=text)
        else:
            self._paste(text, typist)

    def _paste(self, text: str, typist: str) -> None:
        """For text the typing tool gets wrong: ydotool presses keys by their place on a US layout, so "ş" can't be
        typed, and the xdotool most distributions ship (3.2016) types "Ü" and "Ç" in lower case when they are not
        on the keyboard layout. Ctrl+V is the same keys everywhere. The user's clipboard is put back afterwards."""
        if self._clipboard is None:
            raise MissingProgram("wl-clipboard", "xclip")
        saved = self._clipboard.read()
        self._clipboard.write(text)
        try:
            if typist == "xdotool":
                self._runner.check(["xdotool", "key", "--clearmodifiers", "ctrl+v"])
            else:
                self._ydotool_shortcut(_PASTE)
            time.sleep(_PASTE_SETTLE_SECONDS)
        finally:
            # An image on the clipboard reads as no text; writing that back would replace the image with nothing.
            if saved:
                self._clipboard.write(saved)

    def new_line(self) -> None:
        self._with_typist(self._new_line_with)

    def _new_line_with(self, typist: str) -> None:
        if typist == "xdotool":
            self._runner.check(["xdotool", "key", "--clearmodifiers", "shift+Return"])
        elif typist == "wtype":
            self._runner.check(["wtype", "-M", "shift", "-k", "Return", "-m", "shift"])
        else:
            self._ydotool_shortcut(_NEW_LINE)

    def backspace(self, count: int) -> None:
        if count <= 0:
            return
        self._with_typist(lambda typist: self._backspace_with(typist, count))

    def _backspace_with(self, typist: str, count: int) -> None:
        if typist == "xdotool":
            self._runner.check(
                [
                    "xdotool",
                    "key",
                    "--clearmodifiers",
                    "--delay",
                    str(_KEY_DELAY_MS),
                    "--repeat",
                    str(count),
                    "BackSpace",
                ]
            )
        elif typist == "wtype":
            self._runner.check(["wtype", "-d", str(_KEY_DELAY_MS), *(["-k", "BackSpace"] * count)])
        elif self._is_legacy_ydotool():
            self._runner.check(["ydotool", "key", "--key-delay", str(_KEY_DELAY_MS), *["backspace"] * count])
        else:
            self._runner.check(
                ["ydotool", "key", "-d", str(_KEY_DELAY_MS), *[f"{_BACKSPACE}:1", f"{_BACKSPACE}:0"] * count]
            )

    def _ydotool_shortcut(self, keys: tuple[tuple[int, str], ...]) -> None:
        """Presses the keys in order and releases them in reverse, as a shortcut."""
        if self._is_legacy_ydotool():
            self._runner.check(["ydotool", "key", "+".join(name for _, name in keys)])
            return
        events = [f"{code}:1" for code, _ in keys] + [f"{code}:0" for code, _ in reversed(keys)]
        self._runner.check(["ydotool", "key", *events])


def _has_foreign_capital(text: str) -> bool:
    return any(not c.isascii() and c != c.lower() for c in text)


def _sway_focused(node: dict) -> FrontWindow | None:
    if node.get("focused") and node.get("type") in ("con", "floating_con"):
        app_class = str(node.get("app_id") or (node.get("window_properties") or {}).get("class") or "").lower()
        pid = node.get("pid")
        program = _program_name(pid) if isinstance(pid, int) else None
        return FrontWindow(program or app_class, str(node.get("name") or ""), app_class)
    for child in [*node.get("nodes", []), *node.get("floating_nodes", [])]:
        found = _sway_focused(child)
        if found:
            return found
    return None


def _program_name(pid: int) -> str | None:
    try:
        return Path(f"/proc/{pid}/exe").readlink().name.lower()
    except OSError:
        return None
