"""The clipboard and the selection. X11 and Wayland both keep the last selected text as the "primary selection",
so reading what is selected needs no copy shortcut."""

from bilge.desktop.linux.environment import Environment
from bilge.desktop.process import DesktopError, MissingProgram, Runner

_WAYLAND = ("wl-paste", "wl-copy")
_X11 = ("xclip", "xsel")
# What wl-paste and xclip print when there is just nothing (or no text) to paste, as opposed to a real failure
# such as no display to talk to.
_NOTHING_COPIED = ("nothing is copied", "no selection", "no suitable type", "not available", "target string")


class LinuxClipboard:
    def __init__(self, runner: Runner, environment: Environment):
        self._runner = runner
        self._environment = environment

    def _tool(self) -> str:
        # Under Wayland, X11 tools only see the clipboard of X11 apps, so wl-clipboard comes first.
        order = ["wl-copy", *_X11] if self._environment.wayland else [*_X11, "wl-copy"]
        for program in order:
            if self._runner.has(program):
                return program
        raise MissingProgram("wl-clipboard", "xclip", "xsel")

    def read(self) -> str:
        return self._paste(primary=False)

    def selection(self) -> str:
        return self._paste(primary=True)

    def _paste(self, primary: bool) -> str:
        tool = self._tool()
        if tool == "wl-copy":
            # "text" picks whichever text type the app offers, and nothing when only an image was copied.
            argv = ["wl-paste", "--no-newline", *(["--primary"] if primary else []), "--type", "text"]
        elif tool == "xclip":
            argv = ["xclip", "-selection", "primary" if primary else "clipboard", "-out"]
        else:
            argv = ["xsel", "--primary" if primary else "--clipboard", "--output"]
        done = self._runner.run(argv, timeout=5)
        if done.ok:
            return done.stdout
        # An empty clipboard is an error for wl-paste and xclip; for the user it is just nothing.
        message = done.stderr.strip()
        if any(phrase in message.lower() for phrase in _NOTHING_COPIED):
            return ""
        raise DesktopError(f"{argv[0]} could not read the clipboard (exit {done.status}): {message[:200]}")

    def write(self, text: str) -> None:
        tool = self._tool()
        if tool == "wl-copy":
            argv = ["wl-copy", "--type", "text/plain;charset=utf-8"]
        elif tool == "xclip":
            argv = ["xclip", "-selection", "clipboard", "-in"]
        else:
            argv = ["xsel", "--clipboard", "--input"]
        # These stay running to serve the copied text, so their output is not awaited; the exit status of the
        # program started still tells whether it took the text.
        done = self._runner.run(argv, input=text, timeout=5, capture=False)
        if not done.ok:
            raise DesktopError(f"{argv[0]} could not set the clipboard (exit {done.status})")


def image_command(runner: Runner, environment: Environment) -> list[str]:
    """Copies a PNG given on standard input."""
    if environment.wayland and runner.has("wl-copy"):
        return ["wl-copy", "--type", "image/png"]
    if runner.has("xclip"):
        return ["xclip", "-selection", "clipboard", "-target", "image/png", "-in"]
    raise MissingProgram("wl-clipboard", "xclip")
