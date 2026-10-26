"""The files selected in the File Explorer window in front, through the Shell.Application COM object."""

from pathlib import Path
from typing import Any

from bilge.desktop.process import DesktopError
from bilge.desktop.windows import com

# File Explorer's top-level window classes.
_EXPLORER_CLASSES = frozenset({"cabinetwclass", "explorewclass"})


def _default_api():
    from bilge.desktop.windows import win32

    return win32


def _shell():
    import comtypes.client

    return comtypes.client.CreateObject("Shell.Application", dynamic=True)


class ExplorerSelection:
    def __init__(self, api=None, call=com.call):
        self._api = api
        self._call = call

    @property
    def api(self):
        self._api = self._api or _default_api()
        return self._api

    def selected(self) -> tuple[Path, ...]:
        window = self.api.foreground()
        if window is None or window.class_name.lower() not in _EXPLORER_CLASSES:
            return ()
        try:
            paths = self._call(_shell, lambda shell: selection(shell, window.handle))
        except com.ComFailure as error:
            raise DesktopError(f"Could not read Explorer's selection: {error}") from error
        return tuple(Path(path) for path in paths)


def selection(shell: Any, handle: int) -> tuple[str, ...]:
    """Explorer's own way through its windows; tabs of one window share its handle, and the one with a selection
    counts."""
    windows = shell.Windows()
    for index in range(int(windows.Count)):
        view = windows.Item(index)
        if view is None or int(view.HWND) != handle:
            continue
        items = view.Document.SelectedItems()
        paths = tuple(str(items.Item(i).Path) for i in range(int(items.Count)))
        if paths:
            return paths
    return ()
