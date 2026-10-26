"""Do Not Disturb: GNOME and Cinnamon hide banners through a setting, XFCE and dunst have a switch of their own, and
KDE holds notifications back for as long as an app asks it to."""

from bilge.desktop.linux.dbus import Bus
from bilge.desktop.linux.environment import Environment
from bilge.desktop.process import DesktopError, MissingProgram, NotPossibleHere, Runner

_NOTIFICATIONS = ("org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications")
# Schema and key, and whether the key's value is "show" (so true means notifications are on).
_GSETTINGS = {
    "gnome": ("org.gnome.desktop.notifications", "show-banners"),
    "cinnamon": ("org.cinnamon.desktop.notifications", "display-notifications"),
}
_XFCE = ["xfconf-query", "-c", "xfce4-notifyd", "-p", "/do-not-disturb"]


class LinuxDoNotDisturb:
    def __init__(self, runner: Runner, environment: Environment, bus: Bus):
        self._runner = runner
        self._environment = environment
        self._bus = bus
        # KDE releases an inhibition when it is handed back, or when Bilge's connection to the bus closes.
        self._cookie: int | None = None

    def enabled(self) -> bool | None:
        way = self._way()
        try:
            if way == "kde":
                name, path, interface = _NOTIFICATIONS
                return bool(self._bus.get(name, path, interface, "Inhibited"))
            if way in _GSETTINGS:
                schema, key = _GSETTINGS[way]
                return _boolean(self._runner.check(["gsettings", "get", schema, key])) is False
            if way == "xfce":
                return _boolean(self._runner.check(_XFCE)) is True
            if way == "dunst":
                return _boolean(self._runner.check(["dunstctl", "is-paused"])) is True
        except DesktopError:
            return None
        return None

    def set_enabled(self, on: bool) -> None:
        way = self._way()
        if way == "kde":
            self._set_kde(on)
        elif way in _GSETTINGS:
            schema, key = _GSETTINGS[way]
            self._runner.check(["gsettings", "set", schema, key, "false" if on else "true"])
        elif way == "xfce":
            self._runner.check([*_XFCE, "-n", "-t", "bool", "-s", "true" if on else "false"])
        elif way == "dunst":
            self._runner.check(["dunstctl", "set-paused", "true" if on else "false"])
        else:
            env = self._environment
            if env.gnome or env.cinnamon:
                raise MissingProgram("gsettings")
            if env.xfce:
                raise MissingProgram("xfconf-query")
            raise NotPossibleHere(f"No known notification server on {env.desktops}")

    def _set_kde(self, on: bool) -> None:
        name, path, interface = _NOTIFICATIONS
        inhibited = bool(self._bus.get(name, path, interface, "Inhibited"))
        if not inhibited:
            # The bus connection dropped (a timed-out call closes it) or the server restarted: KDE let ours go.
            self._cookie = None
        if on:
            if self._cookie is None:
                self._cookie = int(self._bus.call(name, path, interface, "Inhibit", "ssa{sv}", "bilge", "", {})[0])
            return
        if self._cookie is not None:
            cookie, self._cookie = self._cookie, None
            self._bus.call(name, path, interface, "UnInhibit", "u", cookie)
            return
        if inhibited:
            # Turned on from the panel or by another app, which only they can undo.
            raise NotPossibleHere("Notifications are held back by someone else", "kde")

    def _way(self) -> str | None:
        env, has = self._environment, self._runner.has
        if env.kde:
            return "kde"
        if env.gnome and has("gsettings"):
            return "gnome"
        if env.cinnamon and has("gsettings"):
            return "cinnamon"
        if env.xfce and has("xfconf-query"):
            return "xfce"
        if has("dunstctl"):
            return "dunst"
        return None


def _boolean(output: str) -> bool | None:
    word = output.strip().lower()
    return True if word == "true" else False if word == "false" else None
