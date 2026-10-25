"""Dark mode on desktops that have no dark switch, only themes: XFCE (xfconf) and Cinnamon (gsettings). The dark
variant of the theme in use is chosen ("Greybird" → "Greybird-dark", "Mint-Y-Aqua" → "Mint-Y-Dark-Aqua"), and only
if it is installed; setting a theme that doesn't exist would "succeed" and change nothing."""

from collections.abc import Callable, Iterable
from pathlib import Path

from bilge.desktop.process import DesktopError, MissingProgram, NotPossibleHere, Runner

_XFCE = ["xfconf-query", "-c", "xsettings", "-p", "/Net/ThemeName"]
_CINNAMON_SCHEMA = "org.cinnamon.desktop.interface"
# Mint's themes put the variant before the colour: "Mint-Y-Dark-Aqua".
_MINT_FAMILIES = ("Mint-Y", "Mint-L", "Mint-X")


def theme_dirs(home: Path | None = None) -> list[Path]:
    home = home or Path.home()
    return [home / ".themes", home / ".local/share/themes", Path("/usr/local/share/themes"), Path("/usr/share/themes")]


def is_dark(theme: str) -> bool:
    return "dark" in theme.lower()


def variant(theme: str, dark: bool, installed: Callable[[str], bool]) -> str | None:
    """The installed dark or light counterpart of `theme`; `theme` itself when it already is one; None when there is
    none."""
    if is_dark(theme) == dark:
        return theme
    if dark:
        candidates = [f"{theme}-dark", f"{theme}-Dark"]
        candidates += [
            theme.replace(family, f"{family}-Dark", 1) for family in _MINT_FAMILIES if theme.startswith(family)
        ]
    else:
        candidates = [theme.replace(part, "", 1) for part in ("-dark", "-Dark", "_dark", "-Darker") if part in theme]
    return next((name for name in candidates if name != theme and installed(name)), None)


class ThemeDarkMode:
    def __init__(self, runner: Runner, desktop: str, dirs: Callable[[], Iterable[Path]] = theme_dirs):
        """`desktop` is "xfce" or "cinnamon"."""
        self._runner = runner
        self._desktop = desktop
        self._dirs = dirs

    def _read_command(self) -> list[str]:
        return _XFCE if self._desktop == "xfce" else ["gsettings", "get", _CINNAMON_SCHEMA, "gtk-theme"]

    def current(self) -> str:
        command = self._read_command()
        if not self._runner.has(command[0]):
            raise MissingProgram(command[0])
        theme = self._runner.check(command).strip().strip("'")
        if not theme:
            raise DesktopError("No theme is set")
        return theme

    def dark(self) -> bool:
        return is_dark(self.current())

    def set(self, dark: bool) -> None:
        theme = self.current()
        wanted = variant(theme, dark, self._installed)
        if wanted is None:
            raise NotPossibleHere(f"{theme} has no {'dark' if dark else 'light'} variant", self._desktop)
        if wanted == theme:
            return
        if self._desktop == "xfce":
            self._runner.check([*_XFCE, "-s", wanted])
        else:
            self._runner.check(["gsettings", "set", _CINNAMON_SCHEMA, "gtk-theme", wanted])

    def _installed(self, name: str) -> bool:
        return any((folder / name).is_dir() for folder in self._dirs())
