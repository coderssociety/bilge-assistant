"""Screen brightness: the desktop's own power service on GNOME and KDE, which also shows its on-screen indicator,
then brightnessctl for the built-in panel, then ddcutil for external monitors."""

from collections.abc import Callable

from bilge.desktop.linux.dbus import Bus
from bilge.desktop.linux.environment import Environment
from bilge.desktop.process import DesktopError, MissingProgram, NotPossibleHere, Runner

_GNOME = ("org.gnome.SettingsDaemon.Power", "/org/gnome/SettingsDaemon/Power", "org.gnome.SettingsDaemon.Power.Screen")
_KDE = (
    "org.kde.Solid.PowerManagement",
    "/org/kde/Solid/PowerManagement/Actions/BrightnessControl",
    "org.kde.Solid.PowerManagement.Actions.BrightnessControl",
)
_PROPERTIES = "org.freedesktop.DBus.Properties"
# VCP feature 0x10 is the monitor's luminance.
_LUMINANCE = "10"
# ddcutil talks to each monitor over I2C, which takes a few seconds.
_DDC_SECONDS = 20


class LinuxBrightness:
    def __init__(self, runner: Runner, environment: Environment, bus: Bus):
        self._runner = runner
        self._environment = environment
        self._bus = bus

    def level(self) -> int:
        return self._first(lambda read, _: read())

    def set_level(self, level: int) -> None:
        target = max(0, min(100, level))
        self._first(lambda _, write: write(target))

    def _first[T](self, use: Callable[[Callable[[], int], Callable[[int], None]], T]) -> T:
        """Uses the first way that works; the last failure is kept to say why none did."""
        ways = self._ways()
        if not ways:
            raise MissingProgram("brightnessctl", "ddcutil")
        failure: DesktopError | None = None
        for read, write in ways:
            try:
                return use(read, write)
            except DesktopError as error:
                failure = error
        raise NotPossibleHere(f"No screen whose brightness can be changed: {failure}")

    def _ways(self) -> list[tuple[Callable[[], int], Callable[[int], None]]]:
        env, has = self._environment, self._runner.has
        ways = []
        if env.gnome:
            ways.append((self._gnome_level, self._set_gnome_level))
        if env.kde:
            ways.append((self._kde_level, self._set_kde_level))
        if has("brightnessctl"):
            ways.append((self._backlight_level, self._set_backlight_level))
        if has("ddcutil"):
            ways.append((self._monitor_level, self._set_monitor_level))
        return ways

    def _gnome_level(self) -> int:
        value = int(self._bus.get(*_GNOME, "Brightness"))
        # -1: no panel the settings daemon can dim (a desktop with external monitors).
        if value < 0:
            raise DesktopError("GNOME has no backlight")
        return value

    def _set_gnome_level(self, level: int) -> None:
        self._gnome_level()
        name, path, interface = _GNOME
        self._bus.call(name, path, _PROPERTIES, "Set", "ssv", interface, "Brightness", ("i", level))

    def _kde_level(self) -> int:
        name, path, interface = _KDE
        maximum = int(self._bus.call(name, path, interface, "brightnessMax")[0])
        if maximum <= 0:
            raise DesktopError("KDE has no backlight")
        return round(int(self._bus.call(name, path, interface, "brightness")[0]) * 100 / maximum)

    def _set_kde_level(self, level: int) -> None:
        name, path, interface = _KDE
        maximum = int(self._bus.call(name, path, interface, "brightnessMax")[0])
        if maximum <= 0:
            raise DesktopError("KDE has no backlight")
        self._bus.call(name, path, interface, "setBrightness", "i", round(level * maximum / 100))

    def _backlight_level(self) -> int:
        # "intel_backlight,backlight,400,40%,1000"
        fields = self._runner.check(["brightnessctl", "-m", "-c", "backlight", "info"]).strip().split(",")
        try:
            return int(fields[3].rstrip("%"))
        except (IndexError, ValueError) as error:
            raise DesktopError(f"Unreadable brightnessctl output: {fields}") from error

    def _set_backlight_level(self, level: int) -> None:
        self._runner.check(["brightnessctl", "-q", "-c", "backlight", "set", f"{level}%"])

    def _monitor_level(self) -> int:
        current, maximum = self._monitor_values()
        return round(current * 100 / maximum)

    def _set_monitor_level(self, level: int) -> None:
        _, maximum = self._monitor_values()
        self._runner.check(["ddcutil", "setvcp", _LUMINANCE, str(round(level * maximum / 100))], timeout=_DDC_SECONDS)

    def _monitor_values(self) -> tuple[int, int]:
        # "VCP 10 C 50 100": the current value, then the maximum.
        fields = self._runner.check(["ddcutil", "getvcp", _LUMINANCE, "--brief"], timeout=_DDC_SECONDS).split()
        try:
            current, maximum = int(fields[3]), int(fields[4])
        except (IndexError, ValueError) as error:
            raise DesktopError(f"Unreadable ddcutil output: {fields}") from error
        if maximum <= 0:
            raise DesktopError("The monitor reports no brightness range")
        return current, maximum
