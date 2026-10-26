from types import SimpleNamespace

import pytest

from bilge.core.language import AssistantLanguage
from bilge.desktop.base import WindowAction
from bilge.desktop.linux import environment
from bilge.desktop.linux.windows import LinuxWindows
from bilge.desktop.process import Completed, DesktopError, MissingProgram, NotPossibleHere
from bilge.desktop.windows.system import WindowsWindowControl
from bilge.tools.base import ToolError
from bilge.tools.desktop.windows import window_tool

from .fakes import FakeRunner

X11 = environment.current({"DISPLAY": ":0", "XDG_CURRENT_DESKTOP": "XFCE"})
GNOME_WAYLAND = environment.current({"WAYLAND_DISPLAY": "wayland-0", "XDG_CURRENT_DESKTOP": "ubuntu:GNOME"})
KDE_WAYLAND = environment.current({"WAYLAND_DISPLAY": "wayland-0", "XDG_CURRENT_DESKTOP": "KDE"})
SWAY = environment.current({"WAYLAND_DISPLAY": "wayland-1", "XDG_CURRENT_DESKTOP": "sway"})
HYPRLAND = environment.current({"WAYLAND_DISPLAY": "wayland-1", "XDG_CURRENT_DESKTOP": "Hyprland"})


def test_x11_uses_wmctrl_and_xdotool_minimizes():
    runner = FakeRunner({"wmctrl", "xdotool"})
    windows = LinuxWindows(runner, X11)
    for action in WindowAction:
        windows.act(action)
    assert runner.commands == [
        ["xdotool", "getactivewindow", "windowminimize"],
        ["wmctrl", "-r", ":ACTIVE:", "-b", "add,maximized_vert,maximized_horz"],
        ["wmctrl", "-r", ":ACTIVE:", "-b", "remove,fullscreen"],
        ["wmctrl", "-r", ":ACTIVE:", "-b", "remove,maximized_vert,maximized_horz"],
        ["wmctrl", "-r", ":ACTIVE:", "-b", "toggle,fullscreen"],
        ["wmctrl", "-c", ":ACTIVE:"],
    ]
    with pytest.raises(MissingProgram) as missing:
        LinuxWindows(FakeRunner({"xdotool"}), X11).act(WindowAction.MAXIMIZE)
    assert missing.value.programs == ("wmctrl",)


def test_hyprland_dispatches_and_reads_the_state_for_maximize_and_restore():
    runner = FakeRunner({"hyprctl"}, {"hyprctl dispatch": "ok", "hyprctl activewindow": '{"fullscreen": 0}'})
    windows = LinuxWindows(runner, HYPRLAND)
    windows.act(WindowAction.MINIMIZE)
    windows.act(WindowAction.MAXIMIZE)
    windows.act(WindowAction.RESTORE)
    windows.act(WindowAction.CLOSE)
    dispatched = [argv[2:] for argv in runner.commands if argv[1] == "dispatch"]
    assert dispatched == [["movetoworkspacesilent", "special:minimized"], ["fullscreen", "1"], ["killactive"]]

    runner = FakeRunner({"hyprctl"}, {"hyprctl dispatch": "ok",
                                      "hyprctl activewindow": '{"fullscreen": true, "fullscreenMode": 1}'})  # fmt: skip
    LinuxWindows(runner, HYPRLAND).act(WindowAction.RESTORE)
    assert runner.commands[-1] == ["hyprctl", "dispatch", "fullscreen", "1"]


def test_a_refused_hyprland_dispatch_is_an_error():
    runner = FakeRunner({"hyprctl"}, {"hyprctl dispatch": "Invalid dispatcher"})
    with pytest.raises(DesktopError):
        LinuxWindows(runner, HYPRLAND).act(WindowAction.CLOSE)


def test_sway_commands_and_their_reported_failure():
    runner = FakeRunner({"swaymsg"}, {"swaymsg": '[{"success": true}]'})
    LinuxWindows(runner, SWAY).act(WindowAction.MINIMIZE)
    assert runner.commands == [["swaymsg", "move", "scratchpad"]]
    runner = FakeRunner({"swaymsg"}, {"swaymsg": Completed(2, '[{"success": false, "error": "No window"}]', "")})
    with pytest.raises(DesktopError, match="No window"):
        LinuxWindows(runner, SWAY).act(WindowAction.CLOSE)


def test_kde_wayland_goes_through_kdotool():
    runner = FakeRunner({"kdotool"})
    windows = LinuxWindows(runner, KDE_WAYLAND)
    windows.act(WindowAction.MINIMIZE)
    windows.act(WindowAction.FULL_SCREEN)
    windows.act(WindowAction.MAXIMIZE)
    assert runner.commands[0] == ["kdotool", "getactivewindow", "windowminimize"]
    assert runner.commands[1] == ["kdotool", "getactivewindow", "windowstate", "--toggle", "fullscreen"]
    assert runner.commands[2][:3] == ["kdotool", "kwinscript", "--inline"]
    assert "setMaximize(true, true)" in runner.commands[2][3]
    with pytest.raises(MissingProgram):
        LinuxWindows(FakeRunner(), KDE_WAYLAND).act(WindowAction.CLOSE)


def test_gnome_wayland_is_not_possible_and_the_tool_says_how_to_do_it_instead():
    with pytest.raises(NotPossibleHere) as error:
        LinuxWindows(FakeRunner({"wmctrl", "xdotool"}), GNOME_WAYLAND).act(WindowAction.MINIMIZE)
    tool = window_tool(LinuxWindows(FakeRunner(), GNOME_WAYLAND), AssistantLanguage.TURKISH)
    with pytest.raises(ToolError, match="Süper\\+H"):
        tool.run({"action": "minimize"})
    assert error.value.desktop == "gnome"


def test_the_tool_asks_only_before_closing():
    class Windows:
        def __init__(self):
            self.done = []

        def act(self, action):
            self.done.append(action)

    windows = Windows()
    tool = window_tool(windows, AssistantLanguage.TURKISH)
    assert tool.run({"action": "maximize"}) == "Pencereyi büyüttüm."
    assert tool.question({"action": "maximize"}) is None
    assert tool.question({"action": "close"}).startswith("Öndeki pencere kapatılsın mı?")
    assert windows.done == [WindowAction.MAXIMIZE]


class Api:
    VK_F11, SW_MAXIMIZE, SW_MINIMIZE, SW_RESTORE = 0x7A, 3, 6, 9

    def __init__(self, class_name="Notepad"):
        self.window = SimpleNamespace(handle=5, pid=42, title="Not Defteri", class_name=class_name)
        self.shown, self.closed, self.pressed = [], [], []

    def foreground(self):
        return self.window

    def show(self, window, command):
        self.shown.append((window.handle, command))

    def close(self, window):
        self.closed.append(window.handle)

    def press(self, *keys):
        self.pressed.append(keys)


def test_windows_shows_closes_and_presses_f11_for_full_screen():
    api = Api()
    control = WindowsWindowControl(api)
    control.act(WindowAction.MINIMIZE)
    control.act(WindowAction.RESTORE)
    control.act(WindowAction.FULL_SCREEN)
    control.act(WindowAction.CLOSE)
    assert api.shown == [(5, 6), (5, 9)]
    assert api.pressed == [(0x7A,)]
    assert api.closed == [5]
    with pytest.raises(DesktopError):
        WindowsWindowControl(Api("Shell_TrayWnd")).act(WindowAction.CLOSE)
