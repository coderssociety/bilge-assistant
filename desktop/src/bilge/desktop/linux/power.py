"""Restarting and shutting down through systemd, and logging out through the desktop's own session manager."""

import logging
import os

from bilge.desktop.base import PowerAction
from bilge.desktop.linux.dbus import Bus
from bilge.desktop.linux.environment import Environment
from bilge.desktop.process import DesktopError, MissingProgram, Runner

_SYSTEMD = {PowerAction.RESTART: "reboot", PowerAction.SHUT_DOWN: "poweroff"}
_KDE_SHUTDOWN = ("org.kde.Shutdown", "/Shutdown", "org.kde.Shutdown")
_QDBUS = ("qdbus6", "qdbus-qt6", "qdbus")
log = logging.getLogger(__name__)


class LinuxPower:
    def __init__(self, runner: Runner, environment: Environment, bus: Bus, session_id: str | None = None):
        """`session_id` is logind's id for this session, which ends it where the desktop has no logout of its own."""
        self._runner = runner
        self._environment = environment
        self._bus = bus
        self._session_id = session_id if session_id is not None else os.environ.get("XDG_SESSION_ID", "")

    def act(self, action: PowerAction) -> None:
        if action is PowerAction.LOG_OUT:
            self._log_out()
            return
        # logind lets the user at the screen do this without a password; systemctl and loginctl both ask it.
        for program in ("systemctl", "loginctl"):
            if self._runner.has(program):
                self._runner.check([program, _SYSTEMD[action]])
                return
        raise MissingProgram("systemctl", "loginctl")

    def _log_out(self) -> None:
        env, has = self._environment, self._runner.has
        if env.kde and self._kde_log_out():
            return
        commands = (
            (env.gnome, ["gnome-session-quit", "--logout", "--no-prompt"]),
            (env.cinnamon, ["cinnamon-session-quit", "--logout", "--no-prompt"]),
            (env.xfce, ["xfce4-session-logout", "--logout", "--fast"]),
            (env.sway, ["swaymsg", "exit"]),
            (env.hyprland, ["hyprctl", "dispatch", "exit"]),
        )
        for applies, argv in commands:
            if applies and has(argv[0]):
                self._runner.check(argv)
                return
        if self._session_id and has("loginctl"):
            self._runner.check(["loginctl", "terminate-session", self._session_id])
            return
        raise MissingProgram("gnome-session-quit", "loginctl")

    def _kde_log_out(self) -> bool:
        try:
            self._bus.call(*_KDE_SHUTDOWN, "logout")
            return True
        except DesktopError:
            # Plasma before 5.25 has no org.kde.Shutdown; its session manager takes the logout instead.
            log.info("org.kde.Shutdown did not answer; asking ksmserver", exc_info=True)
        program = next((name for name in _QDBUS if self._runner.has(name)), None)
        if program is None:
            return False
        # Arguments: don't confirm, log out (not reboot or halt), at once.
        return self._runner.run([program, "org.kde.ksmserver", "/KSMServer", "logout", "0", "0", "0"]).ok
