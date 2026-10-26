import sys
from types import SimpleNamespace

import pytest

from bilge.desktop.linux import environment
from bilge.desktop.linux.file_selection import CopiedFiles
from bilge.desktop.process import Completed, DesktopError
from bilge.desktop.windows.com import ComFailure
from bilge.desktop.windows.file_selection import ExplorerSelection, selection

from .fakes import FakeRunner

X11 = environment.current({"DISPLAY": ":0", "XDG_CURRENT_DESKTOP": "XFCE"})
WAYLAND = environment.current({"WAYLAND_DISPLAY": "wayland-0", "XDG_CURRENT_DESKTOP": "KDE"})


@pytest.mark.skipif(sys.platform == "win32", reason="a Linux clipboard listing names POSIX paths")
def test_files_copied_in_the_file_manager_are_read_as_a_uri_list(tmp_path):
    report = tmp_path / "rapor son.pdf"
    report.write_bytes(b"%PDF")
    listing = f"file://{tmp_path}/rapor%20son.pdf\nfile://{tmp_path}/silinmiş.txt\n"
    runner = FakeRunner({"wl-paste", "xclip"}, {"wl-paste": listing})
    assert CopiedFiles(runner, WAYLAND).selected() == (report,)
    assert runner.commands == [["wl-paste", "--no-newline", "--type", "text/uri-list"]]
    runner = FakeRunner({"xclip"}, {"xclip": listing})
    assert CopiedFiles(runner, X11).selected() == (report,)
    assert runner.commands[0][-3:] == ["-target", "text/uri-list", "-out"]


def test_no_copied_files_is_no_selection_and_other_failures_are_errors():
    runner = FakeRunner({"wl-paste"}, {"wl-paste": Completed(1, "", "No suitable type of content copied")})
    assert CopiedFiles(runner, WAYLAND).selected() == ()
    assert CopiedFiles(FakeRunner({"xsel"}), X11).selected() == ()
    runner = FakeRunner({"xclip"}, {"xclip": Completed(1, "", "Can't open display")})
    with pytest.raises(DesktopError):
        CopiedFiles(runner, X11).selected()


def shell_with(*views):
    items = SimpleNamespace(Count=len(views), Item=lambda index: views[index])
    return SimpleNamespace(Windows=lambda: items)


def view(handle, *paths):
    chosen = SimpleNamespace(Count=len(paths), Item=lambda index: SimpleNamespace(Path=paths[index]))
    return SimpleNamespace(HWND=handle, Document=SimpleNamespace(SelectedItems=lambda: chosen))


def test_explorer_selection_comes_from_the_window_in_front():
    shell = shell_with(view(7, r"C:\Users\u\a.pdf"), view(9), view(9, r"C:\Users\u\b.docx", r"C:\Users\u\c.txt"))
    # Tabs of one window share its handle: the tab with a selection counts.
    assert selection(shell, 9) == (r"C:\Users\u\b.docx", r"C:\Users\u\c.txt")
    assert selection(shell, 3) == ()


def test_explorer_is_asked_only_when_it_is_in_front():
    calls = []

    def call(acquire, action):
        calls.append(acquire)
        return action(shell_with(view(5, r"C:\a.pdf")))

    explorer = SimpleNamespace(foreground=lambda: SimpleNamespace(handle=5, class_name="CabinetWClass"))
    assert [str(p) for p in ExplorerSelection(explorer, call).selected()] == [r"C:\a.pdf"]
    notepad = SimpleNamespace(foreground=lambda: SimpleNamespace(handle=5, class_name="Notepad"))
    assert ExplorerSelection(notepad, call).selected() == () and len(calls) == 1

    def broken(acquire, action):
        raise ComFailure("RPC server unavailable")

    with pytest.raises(DesktopError):
        ExplorerSelection(explorer, broken).selected()
