"""The files the user picked in the file manager. Nautilus and Dolphin tell no other program their selection over
D-Bus (Dolphin's MainWindow interface has no such call, Nautilus only shows files), so the files copied with Ctrl+C
are used: every Linux file manager puts them on the clipboard as a text/uri-list."""

from pathlib import Path

from bilge.core.context import screen_context
from bilge.desktop.linux.environment import Environment
from bilge.desktop.process import DesktopError, Runner

_NOTHING_COPIED = ("nothing is copied", "no selection", "no suitable type", "not available", "target")


class CopiedFiles:
    def __init__(self, runner: Runner, environment: Environment):
        self._runner = runner
        self._environment = environment

    def selected(self) -> tuple[Path, ...]:
        argv = self._command()
        if argv is None:
            return ()
        done = self._runner.run(argv, timeout=5)
        if not done.ok:
            if any(phrase in done.stderr.lower() for phrase in _NOTHING_COPIED):
                return ()
            raise DesktopError(f"{argv[0]} could not read copied files (exit {done.status})")
        return tuple(Path(path) for path in screen_context.file_paths(done.stdout) if Path(path).is_file())

    def _command(self) -> list[str] | None:
        """xsel can't ask for a type, so without wl-paste or xclip there are no copied files to read."""
        if self._environment.wayland and self._runner.has("wl-paste"):
            return ["wl-paste", "--no-newline", "--type", "text/uri-list"]
        if self._runner.has("xclip"):
            return ["xclip", "-selection", "clipboard", "-target", "text/uri-list", "-out"]
        return None
