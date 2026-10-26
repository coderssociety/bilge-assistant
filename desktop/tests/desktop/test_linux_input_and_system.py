import sys
from pathlib import Path

import pytest

from bilge.core.language import AssistantLanguage
from bilge.desktop.base import FrontWindow, ScreenshotArea
from bilge.desktop.linux import environment
from bilge.desktop.linux.clipboard import LinuxClipboard
from bilge.desktop.linux.keyboard import LinuxKeyboard, _sway_focused
from bilge.desktop.linux.system import (
    LinuxNotifier,
    LinuxOpener,
    LinuxScreenshots,
    LinuxSession,
    LinuxSettings,
    user_dir,
)
from bilge.desktop.process import Completed, DesktopError, MissingProgram
from bilge.tools.base import ToolError
from bilge.tools.desktop.clipboard import clipboard_tools

from .fakes import FakeRunner

X11 = environment.current({"DISPLAY": ":0", "XDG_CURRENT_DESKTOP": "XFCE"})
GNOME_WAYLAND = environment.current({"WAYLAND_DISPLAY": "wayland-0", "XDG_CURRENT_DESKTOP": "ubuntu:GNOME"})
KDE_WAYLAND = environment.current({"WAYLAND_DISPLAY": "wayland-0", "DISPLAY": ":0", "XDG_CURRENT_DESKTOP": "KDE"})
SWAY = environment.current({"WAYLAND_DISPLAY": "wayland-1", "XDG_CURRENT_DESKTOP": "sway"})


def test_environment_is_read_from_the_session():
    assert GNOME_WAYLAND.wayland and GNOME_WAYLAND.gnome and not GNOME_WAYLAND.kde
    assert KDE_WAYLAND.kde and KDE_WAYLAND.x11


def test_wayland_clipboard_uses_wl_clipboard_and_x11_uses_xclip():
    runner = FakeRunner({"wl-copy", "wl-paste", "xclip"}, {"wl-paste": "kopya"})
    clipboard = LinuxClipboard(runner, GNOME_WAYLAND)
    assert clipboard.read() == "kopya"
    clipboard.selection()
    clipboard.write("yeni")
    assert runner.calls[1][0][:3] == ["wl-paste", "--no-newline", "--primary"]
    assert runner.calls[2] == (["wl-copy", "--type", "text/plain;charset=utf-8"], "yeni")

    runner = FakeRunner({"xclip", "wl-copy"})
    LinuxClipboard(runner, X11).selection()
    assert runner.commands == [["xclip", "-selection", "primary", "-out"]]


def test_empty_clipboard_is_just_empty():
    runner = FakeRunner({"xclip"}, {"xclip": Completed(1, "", "Error: target STRING not available")})
    assert LinuxClipboard(runner, X11).read() == ""


def test_x11_typing_goes_through_xdotool_on_standard_input():
    runner = FakeRunner({"xdotool"})
    keyboard = LinuxKeyboard(runner, X11)
    keyboard.type("Merhaba dünya")
    keyboard.new_line()
    keyboard.backspace(3)
    assert runner.calls[0] == (["xdotool", "type", "--clearmodifiers", "--delay", "8", "--file", "-"], "Merhaba dünya")
    assert runner.commands[1] == ["xdotool", "key", "--clearmodifiers", "shift+Return"]
    assert runner.commands[2][-3:] == ["--repeat", "3", "BackSpace"]


def test_xdotool_pastes_capitals_it_would_type_in_lower_case():
    class Clipboard:
        content = "önceki"

        def read(self):
            return self.content

        def write(self, text):
            self.content = text

    runner = FakeRunner({"xdotool"})
    LinuxKeyboard(runner, X11, Clipboard()).type("ÜÇ harfleri")
    assert runner.commands == [["xdotool", "key", "--clearmodifiers", "ctrl+v"]]


def test_ydotool_pastes_text_it_cannot_type_and_restores_the_clipboard():
    class Clipboard:
        def __init__(self):
            self.content = "önceki"
            self.writes = []

        def read(self):
            return self.content

        def write(self, text):
            self.writes.append(text)
            self.content = text

    runner = FakeRunner({"ydotool"})
    clipboard = Clipboard()
    keyboard = LinuxKeyboard(runner, GNOME_WAYLAND, clipboard)
    keyboard.type("plain ascii")
    keyboard.type("şeker")
    calls = [call for call in runner.calls if call[0] != ["ydotool", "type", "--help"]]
    assert calls[0] == (["ydotool", "type", "-d", "8", "--file", "-"], "plain ascii")
    assert calls[1][0] == ["ydotool", "key", "29:1", "47:1", "47:0", "29:0"]
    assert clipboard.writes == ["şeker", "önceki"]


def test_wtype_is_not_tried_on_gnome_where_the_protocol_is_missing():
    with pytest.raises(MissingProgram) as error:
        LinuxKeyboard(FakeRunner({"wtype"}), GNOME_WAYLAND).type("x")
    assert error.value.programs == ("ydotool",)


LEGACY_YDOTOOL_HELP = "Usage: type [--delay <ms>] [--key-delay <ms>] [--args N] [--file <filepath>] <things to type>"
MODERN_YDOTOOL_HELP = (
    "Usage: type [OPTION]... [STRINGS]...\n  -d, --key-delay=N\n  -H, --key-hold=N\n  -D, --next-delay=N"
)


def test_ydotool_0_1_8_gets_its_own_options_and_key_names():
    runner = FakeRunner({"ydotool"}, {"ydotool type --help": LEGACY_YDOTOOL_HELP})
    keyboard = LinuxKeyboard(runner, GNOME_WAYLAND)
    keyboard.type("abc")
    keyboard.new_line()
    keyboard.backspace(2)
    assert runner.commands[1:] == [
        ["ydotool", "type", "--key-delay", "8", "--file", "-"],
        ["ydotool", "key", "shift+enter"],
        ["ydotool", "key", "--key-delay", "8", "backspace", "backspace"],
    ]
    assert runner.commands.count(["ydotool", "type", "--help"]) == 1


def test_ydotool_1_x_takes_event_codes():
    runner = FakeRunner({"ydotool"}, {"ydotool type --help": MODERN_YDOTOOL_HELP})
    LinuxKeyboard(runner, GNOME_WAYLAND).new_line()
    assert runner.commands[-1] == ["ydotool", "key", "42:1", "28:1", "28:0", "42:0"]


def test_shortcuts_are_pressed_with_each_typing_tool():
    runner = FakeRunner({"xdotool"})
    LinuxKeyboard(runner, X11).press("ctrl", "shift", "tab")
    assert runner.commands == [["xdotool", "key", "--clearmodifiers", "ctrl+shift+Tab"]]

    runner = FakeRunner({"wtype"})
    LinuxKeyboard(runner, SWAY).press("alt", "left")
    assert runner.commands == [["wtype", "-M", "alt", "-k", "Left", "-m", "alt"]]

    runner = FakeRunner({"ydotool"}, {"ydotool type --help": MODERN_YDOTOOL_HELP})
    LinuxKeyboard(runner, GNOME_WAYLAND).press("ctrl", "T")
    assert runner.commands[-1] == ["ydotool", "key", "29:1", "20:1", "20:0", "29:0"]

    runner = FakeRunner({"ydotool"}, {"ydotool type --help": LEGACY_YDOTOOL_HELP})
    LinuxKeyboard(runner, GNOME_WAYLAND).press("page_down")
    assert runner.commands[-1] == ["ydotool", "key", "pagedown"]


def test_an_unknown_key_is_refused_before_anything_is_pressed():
    runner = FakeRunner({"xdotool"})
    with pytest.raises(DesktopError):
        LinuxKeyboard(runner, X11).press("ctrl", "ş")
    assert runner.commands == []


def test_wtype_is_skipped_on_kde_and_ydotool_takes_over_when_wtype_is_refused():
    runner = FakeRunner({"wtype", "ydotool"})
    LinuxKeyboard(runner, KDE_WAYLAND).type("abc")
    assert all(argv[0] == "ydotool" for argv in runner.commands)

    refused = Completed(1, "", "Compositor does not support the virtual keyboard protocol")
    runner = FakeRunner({"wtype", "ydotool"}, {"wtype": refused})
    LinuxKeyboard(runner, SWAY).type("abc")
    assert runner.commands[0][0] == "wtype"
    assert runner.calls[-1] == (["ydotool", "type", "-d", "8", "--file", "-"], "abc")


def test_the_last_typing_failure_is_reported_when_every_tool_fails():
    runner = FakeRunner({"wtype", "ydotool"}, {"wtype": Completed(1, "", "no protocol"),
                                               "ydotool type -d": Completed(2, "", "failed to connect socket")})  # fmt: skip
    with pytest.raises(DesktopError, match="socket"):
        LinuxKeyboard(runner, SWAY).type("abc")


def test_window_class_comes_from_xprop_where_xdotool_is_too_old():
    runner = FakeRunner({"xdotool", "xprop"}, {"xdotool getactivewindow": "77\n", "xdotool getwindowpid": "",
                                                "xprop": 'WM_CLASS(STRING) = "kgx", "Kgx"\n'})  # fmt: skip
    assert LinuxKeyboard(runner, X11).front_window().app_class == "kgx"


def test_front_window_on_x11_and_sway_but_not_gnome_wayland():
    runner = FakeRunner({"xdotool"}, {"xdotool getactivewindow": "123\n", "xdotool getwindowclassname": "Gedit\n",
                                       "xdotool getwindowpid": "", "xdotool getwindowname": "notlar.txt"})  # fmt: skip
    assert LinuxKeyboard(runner, X11).front_window() == FrontWindow("gedit", "notlar.txt", "gedit")
    assert LinuxKeyboard(FakeRunner({"xdotool"}), GNOME_WAYLAND).front_window() is None
    tree = {"type": "root", "nodes": [{"type": "output", "nodes": [
        {"type": "con", "focused": False, "app_id": "foot", "name": "a"},
        {"type": "con", "focused": True, "app_id": "org.gnome.TextEditor", "name": "b"}]}]}  # fmt: skip
    assert _sway_focused(tree) == FrontWindow("org.gnome.texteditor", "b", "org.gnome.texteditor")


def test_dark_mode_on_gnome_and_kde():
    runner = FakeRunner({"gsettings"}, {"gsettings get": "'prefer-dark'\n"})
    session = LinuxSession(runner, GNOME_WAYLAND)
    assert session.dark_mode() is True
    session.set_dark_mode(False)
    assert runner.commands[-1] == ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "default"]
    runner = FakeRunner({"plasma-apply-colorscheme"})
    LinuxSession(runner, KDE_WAYLAND).set_dark_mode(True)
    assert runner.commands == [["plasma-apply-colorscheme", "BreezeDark"]]


def test_lock_falls_back_to_xdg_screensaver():
    runner = FakeRunner({"loginctl", "xdg-screensaver"}, {"loginctl": Completed(1, "", "no session")})
    LinuxSession(runner, X11).lock()
    assert runner.commands[-1] == ["xdg-screensaver", "lock"]


def test_screenshot_tool_follows_the_desktop(tmp_path):
    shot = tmp_path / "s.png"

    class Capturing(FakeRunner):
        def run(self, argv, input=None, timeout=15, capture=True):
            if argv[0] != "slurp":
                Path(argv[-1]).write_bytes(b"png")
            return super().run(argv, input, timeout, capture)

    runner = Capturing({"spectacle", "gnome-screenshot"})
    assert LinuxScreenshots(runner, KDE_WAYLAND).capture(ScreenshotArea.SELECTION, shot)
    assert runner.commands[-1] == ["spectacle", "-b", "-n", "-r", "-o", str(shot)]
    runner = Capturing({"grim", "slurp"}, {"slurp": "10,10 200x100"})
    assert LinuxScreenshots(runner, SWAY).capture(ScreenshotArea.SELECTION, shot)
    assert runner.commands[-1] == ["grim", "-g", "10,10 200x100", str(shot)]


def test_cancelled_selection_takes_no_screenshot(tmp_path):
    runner = FakeRunner({"grim", "slurp"}, {"slurp": Completed(1, "", "selection cancelled")})
    assert not LinuxScreenshots(runner, SWAY).capture(ScreenshotArea.SELECTION, tmp_path / "s.png")


def test_settings_pages_open_in_gnome_and_kde():
    runner = FakeRunner({"gnome-control-center"})
    assert LinuxSettings(runner, GNOME_WAYLAND).open("wifi")
    assert not LinuxSettings(runner, GNOME_WAYLAND).open("printers")
    assert runner.spawned == [["gnome-control-center", "wifi"], ["gnome-control-center"]]
    runner = FakeRunner({"systemsettings"})
    assert LinuxSettings(runner, KDE_WAYLAND).open("sound")
    assert runner.spawned == [["systemsettings", "kcm_pulseaudio"]]


class Bus:
    def __init__(self, fails=False):
        self.fails = fails
        self.calls = []

    def call(self, *args):
        if self.fails:
            raise DesktopError("no service")
        self.calls.append(args)


@pytest.mark.skipif(sys.platform == "win32", reason="file:// addresses of Linux paths")
def test_reveal_asks_the_file_manager_or_opens_the_folder(tmp_path):
    bus = Bus()
    LinuxOpener(FakeRunner({"xdg-open"}), bus).reveal(tmp_path / "a b.sh")
    assert bus.calls[0][3] == "ShowItems" and bus.calls[0][5][0].endswith("/a%20b.sh")
    runner = FakeRunner({"xdg-open"})
    LinuxOpener(runner, Bus(fails=True)).reveal(tmp_path / "x.sh")
    assert runner.spawned == [["xdg-open", str(tmp_path)]]


def test_notifications_fall_back_to_notify_send():
    runner = FakeRunner({"notify-send"})
    LinuxNotifier(runner, Bus(fails=True)).notify("Bilge", "Çay hazır")
    assert runner.commands == [["notify-send", "--app-name", "Bilge", "Bilge", "Çay hazır"]]


def test_translated_user_folders_come_from_user_dirs(tmp_path):
    (tmp_path / ".config").mkdir()
    (tmp_path / ".config" / "user-dirs.dirs").write_text('XDG_DESKTOP_DIR="$HOME/Masaüstü"\n', encoding="utf-8")
    environ = {"HOME": str(tmp_path)}
    assert user_dir("DESKTOP", "Desktop", environ) == tmp_path / "Masaüstü"
    assert user_dir("DOWNLOAD", "Downloads", environ) == tmp_path / "Downloads"


@pytest.mark.parametrize(
    "stderr", ["Nothing is copied", "No suitable type of content copied", "Error: target STRING not available"]
)
def test_nothing_copied_reads_as_empty(stderr):
    runner = FakeRunner({"wl-copy", "wl-paste"}, {"wl-paste": Completed(1, "", stderr)})
    assert LinuxClipboard(runner, GNOME_WAYLAND).read() == ""


def test_a_clipboard_program_that_fails_is_an_error_not_an_empty_clipboard():
    runner = FakeRunner({"xclip"}, {"xclip": Completed(1, "", "Error: Can't open display: (null)")})
    with pytest.raises(DesktopError, match="open display"):
        LinuxClipboard(runner, X11).read()
    runner = FakeRunner({"wl-copy"}, {"wl-copy": Completed(1, "", "")})
    with pytest.raises(DesktopError):
        LinuxClipboard(runner, GNOME_WAYLAND).write("metin")


def test_the_clipboard_tool_says_reading_failed():
    runner = FakeRunner({"xclip"}, {"xclip": Completed(1, "", "Error: Can't open display")})
    tools = {t.name: t for t in clipboard_tools(LinuxClipboard(runner, X11), AssistantLanguage.TURKISH, lambda: None)}
    with pytest.raises(ToolError, match="Panoyu okuyamadım"):
        tools["readClipboard"].run({})
