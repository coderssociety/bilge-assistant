"""Minimizing, maximizing, full screen and closing the window in front. X11 lets any program do it (wmctrl,
xdotool); on Wayland only the compositor can, so Hyprland and Sway are asked through their own commands and KDE
through kdotool. GNOME on Wayland offers no way at all."""

import json

from bilge.desktop.base import WindowAction
from bilge.desktop.linux.environment import Environment
from bilge.desktop.process import DesktopError, MissingProgram, NotPossibleHere, Runner

_ACTIVE = ":ACTIVE:"
_MAXIMIZED = "maximized_vert,maximized_horz"
# Hyprland has no minimized state; a hidden special workspace is what its users use for it.
_HYPRLAND_MINIMIZED = "special:minimized"
_SWAY = {
    WindowAction.MINIMIZE: ["move", "scratchpad"],
    WindowAction.MAXIMIZE: ["fullscreen", "enable"],
    WindowAction.RESTORE: ["fullscreen", "disable"],
    WindowAction.FULL_SCREEN: ["fullscreen", "toggle"],
    WindowAction.CLOSE: ["kill"],
}
# KWin's scripting API: Plasma 6 calls the window in front activeWindow, Plasma 5 activeClient.
_KWIN_WINDOW = "const w = workspace.activeWindow || workspace.activeClient; "
_KWIN_SCRIPTS = {
    WindowAction.MAXIMIZE: _KWIN_WINDOW + "w.setMaximize(true, true);",
    WindowAction.RESTORE: _KWIN_WINDOW + "w.fullScreen = false; w.setMaximize(false, false);",
}
_NONE, _MAXIMIZED_STATE, _FULL_SCREEN_STATE = 0, 1, 2


class LinuxWindows:
    def __init__(self, runner: Runner, environment: Environment):
        self._runner = runner
        self._environment = environment

    def act(self, action: WindowAction) -> None:
        env = self._environment
        if env.hyprland and self._runner.has("hyprctl"):
            self._hyprland(action)
        elif env.sway and self._runner.has("swaymsg"):
            self._sway(action)
        elif env.wayland and env.kde:
            self._kde(action)
        elif not env.wayland:
            self._x11(action)
        else:
            raise NotPossibleHere(f"No window control on {env.desktops}", "gnome" if env.gnome else "")

    def _hyprland(self, action: WindowAction) -> None:
        if action is WindowAction.MINIMIZE:
            self._dispatch("movetoworkspacesilent", _HYPRLAND_MINIMIZED)
        elif action is WindowAction.CLOSE:
            self._dispatch("killactive")
        elif action is WindowAction.FULL_SCREEN:
            self._dispatch("fullscreen", "0")
        else:
            # "fullscreen 0/1" toggle full screen / maximized, so the current state decides what to send.
            state = self._hyprland_state()
            if state == _FULL_SCREEN_STATE:
                self._dispatch("fullscreen", "0")
            if action is WindowAction.MAXIMIZE and state != _MAXIMIZED_STATE or action is WindowAction.RESTORE and state == _MAXIMIZED_STATE:
                self._dispatch("fullscreen", "1")

    def _hyprland_state(self) -> int:
        try:
            window = json.loads(self._runner.check(["hyprctl", "activewindow", "-j"]))
        except ValueError as error:
            raise DesktopError(f"Unreadable hyprctl answer: {error}") from error
        if not isinstance(window, dict) or not window:
            raise DesktopError("No window in front")
        fullscreen = window.get("fullscreen")
        if isinstance(fullscreen, bool):
            # Before Hyprland 0.42: a flag, and fullscreenMode 1 meaning maximized.
            if not fullscreen:
                return _NONE
            return _MAXIMIZED_STATE if window.get("fullscreenMode") == 1 else _FULL_SCREEN_STATE
        if not isinstance(fullscreen, int):
            return _NONE
        # Later: 1 maximized, 2 full screen (3 when the app asked for full screen too).
        return _MAXIMIZED_STATE if fullscreen == 1 else _FULL_SCREEN_STATE if fullscreen >= 2 else _NONE

    def _dispatch(self, *arguments: str) -> None:
        # hyprctl reports a refused dispatch in its output, not always in its exit status.
        answer = self._runner.check(["hyprctl", "dispatch", *arguments]).strip()
        if answer != "ok":
            raise DesktopError(f"hyprctl dispatch {' '.join(arguments)}: {answer[:200]}")

    def _sway(self, action: WindowAction) -> None:
        done = self._runner.run(["swaymsg", *_SWAY[action]])
        try:
            replies = json.loads(done.stdout) if done.stdout.strip() else []
        except ValueError:
            replies = []
        refused = [r for r in replies if isinstance(r, dict) and not r.get("success", False)]
        if not done.ok or refused:
            detail = refused[0].get("error", "") if refused else done.stderr
            raise DesktopError(f"swaymsg {action}: {str(detail)[:200]}")

    def _kde(self, action: WindowAction) -> None:
        if not self._runner.has("kdotool"):
            raise MissingProgram("kdotool")
        script = _KWIN_SCRIPTS.get(action)
        if script is not None:
            self._runner.check(["kdotool", "kwinscript", "--inline", script])
            return
        command = {
            WindowAction.MINIMIZE: ["windowminimize"],
            WindowAction.CLOSE: ["windowclose"],
            WindowAction.FULL_SCREEN: ["windowstate", "--toggle", "fullscreen"],
        }[action]
        self._runner.check(["kdotool", "getactivewindow", *command])

    def _x11(self, action: WindowAction) -> None:
        if action is WindowAction.MINIMIZE:
            # wmctrl can't minimize; EWMH leaves it to the window manager, which xdotool asks for.
            if not self._runner.has("xdotool"):
                raise MissingProgram("xdotool")
            self._runner.check(["xdotool", "getactivewindow", "windowminimize"])
            return
        if not self._runner.has("wmctrl"):
            raise MissingProgram("wmctrl")
        if action is WindowAction.CLOSE:
            self._runner.check(["wmctrl", "-c", _ACTIVE])
        elif action is WindowAction.MAXIMIZE:
            self._runner.check(["wmctrl", "-r", _ACTIVE, "-b", f"add,{_MAXIMIZED}"])
        elif action is WindowAction.FULL_SCREEN:
            self._runner.check(["wmctrl", "-r", _ACTIVE, "-b", "toggle,fullscreen"])
        else:
            self._runner.check(["wmctrl", "-r", _ACTIVE, "-b", "remove,fullscreen"])
            self._runner.check(["wmctrl", "-r", _ACTIVE, "-b", f"remove,{_MAXIMIZED}"])
