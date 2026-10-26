"""Session and system controls: locking, sleep, dark mode, Wi-Fi, settings pages, screenshots, notifications and
opening files or addresses."""

import os
import shutil
from collections.abc import Callable
from pathlib import Path
from urllib.parse import quote

from bilge.desktop.base import ScreenshotArea
from bilge.desktop.linux.clipboard import image_command
from bilge.desktop.linux.dbus import Bus
from bilge.desktop.linux.environment import Environment
from bilge.desktop.linux.screenshot_portal import PortalScreenshot, PortalUnavailable
from bilge.desktop.linux.theme import ThemeDarkMode
from bilge.desktop.process import Completed, DesktopError, MissingProgram, NotPossibleHere, Runner

_GNOME_SCHEMA = "org.gnome.desktop.interface"
# The user drags a rectangle, which can take a while.
_SELECTION_SECONDS = 60


# Tiling compositors have no locker of their own; loginctl asks for a lock that only an idle daemon set up to answer
# would carry out, while reporting success either way.
_LOCKERS = {"hyprland": ("hyprlock", "swaylock"), "sway": ("swaylock",)}
# swaylock -f forks once the screen is locked; hyprlock keeps running until unlocked.
_LOCK_COMMANDS = {"hyprlock": ["hyprlock"], "swaylock": ["swaylock", "-f"]}


class LinuxSession:
    def __init__(self, runner: Runner, environment: Environment, themes: Callable[[str], ThemeDarkMode] | None = None):
        self._runner = runner
        self._environment = environment
        self._themes = themes or (lambda desktop: ThemeDarkMode(runner, desktop))

    def _theme_desktop(self) -> str | None:
        env = self._environment
        return "xfce" if env.xfce else "cinnamon" if env.cinnamon else None

    def lock(self) -> None:
        env = self._environment
        compositor = "hyprland" if env.hyprland else "sway" if env.sway else None
        if compositor is not None:
            self._lock_with(_LOCKERS[compositor])
            return
        if self._runner.has("loginctl") and self._runner.run(["loginctl", "lock-session"]).ok:
            return
        if self._runner.has("xdg-screensaver"):
            self._runner.check(["xdg-screensaver", "lock"])
            return
        raise MissingProgram("loginctl", "xdg-screensaver")

    def _lock_with(self, lockers: tuple[str, ...]) -> None:
        locker = next((program for program in lockers if self._runner.has(program)), None)
        if locker is None:
            raise MissingProgram(*lockers)
        argv = _LOCK_COMMANDS[locker]
        if argv[-1] == "-f":
            self._runner.check(argv)
        else:
            self._runner.spawn(argv)

    def suspend(self) -> None:
        if not self._runner.has("systemctl"):
            raise MissingProgram("systemctl")
        self._runner.check(["systemctl", "suspend"])

    def dark_mode(self) -> bool | None:
        if self._environment.kde:
            for program in ("kreadconfig6", "kreadconfig5"):
                if self._runner.has(program):
                    scheme = self._runner.run([program, "--group", "General", "--key", "ColorScheme"]).stdout
                    return "dark" in scheme.lower()
            return None
        themed = self._theme_desktop()
        if themed is not None:
            try:
                return self._themes(themed).dark()
            except DesktopError:
                return None
        if self._runner.has("gsettings"):
            done = self._runner.run(["gsettings", "get", _GNOME_SCHEMA, "color-scheme"])
            return "dark" in done.stdout if done.ok else None
        return None

    def set_dark_mode(self, dark: bool) -> None:
        if self._environment.kde:
            if not self._runner.has("plasma-apply-colorscheme"):
                raise MissingProgram("plasma-apply-colorscheme")
            self._runner.check(["plasma-apply-colorscheme", "BreezeDark" if dark else "BreezeLight"])
            return
        themed = self._theme_desktop()
        if themed is not None:
            # GNOME's color-scheme key exists here too but nothing reads it, so setting it would change nothing.
            self._themes(themed).set(dark)
            return
        if not self._runner.has("gsettings"):
            raise MissingProgram("gsettings")
        # GNOME 42 and later; apps that follow the portal setting switch at once.
        self._runner.check(["gsettings", "set", _GNOME_SCHEMA, "color-scheme", "prefer-dark" if dark else "default"])


class LinuxNetwork:
    def __init__(self, runner: Runner):
        self._runner = runner

    def wifi_enabled(self) -> bool | None:
        if not self._runner.has("nmcli"):
            return None
        done = self._runner.run(["nmcli", "radio", "wifi"])
        return done.stdout.strip() == "enabled" if done.ok else None

    def wifi_name(self) -> str | None:
        if self._runner.has("nmcli"):
            done = self._runner.run(["nmcli", "-t", "-f", "ACTIVE,SSID", "device", "wifi"])
            if done.ok:
                for line in done.stdout.splitlines():
                    active, _, name = line.partition(":")
                    if active == "yes" and name:
                        # Terse output escapes colons in the name.
                        return name.replace("\\:", ":")
                return None
        if self._runner.has("iwgetid"):
            done = self._runner.run(["iwgetid", "--raw"])
            return (done.stdout.strip() or None) if done.ok else None
        return None

    def set_wifi(self, enabled: bool) -> None:
        if not self._runner.has("nmcli"):
            raise MissingProgram("nmcli")
        self._runner.check(["nmcli", "radio", "wifi", "on" if enabled else "off"])


class LinuxScreenshots:
    def __init__(self, runner: Runner, environment: Environment, portal: Callable[[bool], Path | None] | None = None):
        """`portal` takes a screenshot through the desktop portal (interactive or not); None when cancelled."""
        self._runner = runner
        self._environment = environment
        self._portal = portal or PortalScreenshot().take

    def capture(self, area: ScreenshotArea, destination: Path) -> bool:
        if self._portal_only():
            return self._portal_capture(area, destination)
        argv = self._command(area, destination)
        if argv is None:
            return False
        timeout = _SELECTION_SECONDS if area is ScreenshotArea.SELECTION else 15
        done = self._runner.run(argv, timeout=timeout)
        if done.ok and destination.exists():
            return True
        # Cancelling a selection exits with an error, or quietly, and writes nothing; anything else is a failure.
        if area is ScreenshotArea.SELECTION and _cancelled(done):
            return False
        raise DesktopError(f"{argv[0]} took no screenshot (exit {done.status}): {done.stderr.strip()[:200]}")

    def _portal_only(self) -> bool:
        env, has = self._environment, self._runner.has
        if not env.wayland:
            return False
        if env.kde:
            return not has("spectacle")
        if env.gnome:
            return not has("gnome-screenshot")
        return not has("grim")

    def _portal_capture(self, area: ScreenshotArea, destination: Path) -> bool:
        try:
            saved = self._portal(area is not ScreenshotArea.WHOLE_SCREEN)
        except PortalUnavailable as error:
            raise MissingProgram("xdg-desktop-portal", "gnome-screenshot", "spectacle", "grim") from error
        if saved is None:
            return False
        try:
            shutil.move(saved, destination)
        except OSError as error:
            raise DesktopError(f"Could not move the portal's screenshot {saved}: {error}") from error
        return True

    def _command(self, area: ScreenshotArea, file: Path) -> list[str] | None:
        """None when the user cancelled choosing an area."""
        has = self._runner.has
        path = str(file)
        env = self._environment
        if env.kde and has("spectacle"):
            mode = {
                ScreenshotArea.WHOLE_SCREEN: "-f",
                ScreenshotArea.FRONT_WINDOW: "-a",
                ScreenshotArea.SELECTION: "-r",
            }
            return ["spectacle", "-b", "-n", mode[area], "-o", path]
        if env.gnome and has("gnome-screenshot"):
            mode = {
                ScreenshotArea.WHOLE_SCREEN: [],
                ScreenshotArea.FRONT_WINDOW: ["-w"],
                ScreenshotArea.SELECTION: ["-a"],
            }
            return ["gnome-screenshot", *mode[area], "-f", path]
        # grim needs wlroots' screencopy, which GNOME and KDE don't have.
        if env.wayland and not env.gnome and not env.kde and has("grim"):
            if area is ScreenshotArea.SELECTION:
                if not has("slurp"):
                    raise MissingProgram("slurp")
                region = self._runner.run(["slurp"], timeout=_SELECTION_SECONDS)
                if not region.ok:
                    if _cancelled(region):
                        return None
                    raise DesktopError(f"slurp failed: {region.stderr.strip()[:200]}")
                return ["grim", "-g", region.stdout.strip(), path]
            return ["grim", path]
        if not env.wayland:
            if has("maim"):
                # Only a window capture needs xdotool, so the window is only looked up then.
                window = ["-i", self._active_window()] if area is ScreenshotArea.FRONT_WINDOW else []
                mode = {ScreenshotArea.WHOLE_SCREEN: [], ScreenshotArea.FRONT_WINDOW: window,
                        ScreenshotArea.SELECTION: ["-s"]}  # fmt: skip
                return ["maim", *mode[area], path]
            if has("scrot"):
                mode = {
                    ScreenshotArea.WHOLE_SCREEN: [],
                    ScreenshotArea.FRONT_WINDOW: ["-u"],
                    ScreenshotArea.SELECTION: ["-s"],
                }
                return ["scrot", *mode[area], path]
        raise MissingProgram("gnome-screenshot", "spectacle", "grim", "maim", "scrot")

    def _active_window(self) -> str:
        if not self._runner.has("xdotool"):
            raise MissingProgram("xdotool")
        return self._runner.check(["xdotool", "getactivewindow"]).strip()

    def copy_image(self, image: Path) -> None:
        self._runner.feed(image_command(self._runner, self._environment), image)


# GNOME Settings panel and KDE System Settings module for each page the assistant knows.
_GNOME_PANELS = {
    "wifi": "wifi", "bluetooth": "bluetooth", "network": "network", "sound": "sound", "displays": "display",
    "battery": "power", "notifications": "notifications", "privacy": "privacy", "keyboard": "keyboard",
    "general": "system", "wallpaper": "background", "accessibility": "universal-access", "mouse": "mouse",
    "trackpad": "mouse", "storage": "usage", "focus": "notifications",
}  # fmt: skip
_KDE_MODULES = {
    "wifi": "kcm_networkmanagement", "network": "kcm_networkmanagement", "bluetooth": "kcm_bluetooth",
    "sound": "kcm_pulseaudio", "displays": "kcm_kscreen", "battery": "kcm_powerdevilprofilesconfig",
    "notifications": "kcm_notifications", "keyboard": "kcm_keyboard", "wallpaper": "kcm_wallpaper",
    "accessibility": "kcm_access", "mouse": "kcm_mouse", "trackpad": "kcm_touchpad", "general": "kcm_about-distro",
    "privacy": "kcm_screenlocker", "focus": "kcm_notifications",
}  # fmt: skip


# Cinnamon's settings modules, XFCE's separate settings programs, and stand-alone tools any desktop may have.
_CINNAMON_MODULES = {
    "wifi": "network", "network": "network", "bluetooth": "bluetooth", "sound": "sound", "displays": "display",
    "battery": "power", "notifications": "notifications", "privacy": "privacy", "keyboard": "keyboard",
    "general": "info", "wallpaper": "backgrounds", "accessibility": "accessibility", "mouse": "mouse",
    "trackpad": "mouse",
}  # fmt: skip
_XFCE_PROGRAMS = {
    "displays": "xfce4-display-settings", "mouse": "xfce4-mouse-settings", "trackpad": "xfce4-mouse-settings",
    "keyboard": "xfce4-keyboard-settings", "battery": "xfce4-power-manager-settings",
    "notifications": "xfce4-notifyd-config", "wallpaper": "xfdesktop-settings",
    "accessibility": "xfce4-accessibility-settings",
}  # fmt: skip
_STANDALONE = {
    "wifi": "nm-connection-editor", "network": "nm-connection-editor", "bluetooth": "blueman-manager",
    "sound": "pavucontrol",
}  # fmt: skip


class LinuxSettings:
    def __init__(self, runner: Runner, environment: Environment):
        self._runner = runner
        self._environment = environment

    def open(self, pane: str) -> bool:
        has, env = self._runner.has, self._environment
        if pane == "softwareUpdate":
            for argv in (["gnome-software", "--mode=updates"], ["plasma-discover", "--mode", "update"]):
                if has(argv[0]):
                    self._runner.spawn(argv)
                    return True
        if env.kde and has("systemsettings"):
            return self._spawn_page(["systemsettings"], _KDE_MODULES.get(pane))
        if env.gnome and has("gnome-control-center"):
            return self._spawn_page(["gnome-control-center"], _GNOME_PANELS.get(pane))
        if env.xfce and has("xfce4-settings-manager"):
            program = _XFCE_PROGRAMS.get(pane) or _STANDALONE.get(pane)
            if program and has(program):
                self._runner.spawn([program])
                return True
            self._runner.spawn(["xfce4-settings-manager"])
            return False
        if env.cinnamon and has("cinnamon-settings"):
            return self._spawn_page(["cinnamon-settings"], _CINNAMON_MODULES.get(pane))
        standalone = _STANDALONE.get(pane)
        if standalone and has(standalone):
            self._runner.spawn([standalone])
            return True
        if env.tiling:
            raise NotPossibleHere(f"No settings app on {env.desktops}", "tiling")
        if has("gnome-control-center"):
            return self._spawn_page(["gnome-control-center"], _GNOME_PANELS.get(pane))
        raise MissingProgram("gnome-control-center", "systemsettings", "xfce4-settings-manager", "cinnamon-settings")

    def _spawn_page(self, argv: list[str], page: str | None) -> bool:
        self._runner.spawn([*argv, *([page] if page else [])])
        return page is not None


class LinuxOpener:
    def __init__(self, runner: Runner, bus: Bus):
        self._runner = runner
        self._bus = bus

    def open(self, target: str) -> None:
        for argv in (["xdg-open", target], ["gio", "open", target]):
            if self._runner.has(argv[0]):
                self._runner.spawn(argv)
                return
        raise MissingProgram("xdg-open")

    def reveal(self, path: Path) -> None:
        uri = "file://" + quote(str(path.resolve()))
        try:
            self._bus.call("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                           "org.freedesktop.FileManager1", "ShowItems", "ass", [uri], "")  # fmt: skip
        except DesktopError:
            # No file manager answers on the bus (some lightweight desktops): open the folder instead.
            self.open(str(path.parent))


class LinuxNotifier:
    def __init__(self, runner: Runner, bus: Bus, app_name: str = "Bilge"):
        self._runner = runner
        self._bus = bus
        self._app_name = app_name

    def notify(self, title: str, body: str) -> None:
        try:
            self._bus.call("org.freedesktop.Notifications", "/org/freedesktop/Notifications",
                           "org.freedesktop.Notifications", "Notify", "susssasa{sv}i",
                           self._app_name, 0, "", title, body, [], {}, -1)  # fmt: skip
        except DesktopError:
            if not self._runner.has("notify-send"):
                raise
            self._runner.run(["notify-send", "--app-name", self._app_name, title, body])


class LinuxFolders:
    def home(self) -> Path:
        return Path.home()

    def desktop(self) -> Path:
        return user_dir("DESKTOP", "Desktop")

    def downloads(self) -> Path:
        return user_dir("DOWNLOAD", "Downloads")

    def documents(self) -> Path:
        return user_dir("DOCUMENTS", "Documents")

    def pictures(self) -> Path:
        return user_dir("PICTURES", "Pictures")

    def music(self) -> Path:
        return user_dir("MUSIC", "Music")

    def videos(self) -> Path:
        return user_dir("VIDEOS", "Videos")


def _cancelled(done: Completed) -> bool:
    """slurp and maim say "cancelled"; spectacle and gnome-screenshot just end without a file."""
    message = done.stderr.strip().lower()
    return not message or "cancel" in message


def user_dir(name: str, fallback: str, environ: dict[str, str] | None = None) -> Path:
    """An XDG user folder ("DESKTOP", "DOWNLOAD", "DOCUMENTS", "PICTURES", "MUSIC", "VIDEOS"), which may be translated
    ("Masaüstü")."""
    env = os.environ if environ is None else environ
    home = Path(env.get("HOME", str(Path.home())))
    config = Path(env.get("XDG_CONFIG_HOME") or home / ".config") / "user-dirs.dirs"
    try:
        for line in config.read_text(encoding="utf-8").splitlines():
            key, _, value = line.partition("=")
            if key.strip() == f"XDG_{name}_DIR":
                folder = value.strip().strip('"').replace("$HOME", str(home))
                return Path(folder)
    except OSError:
        pass
    return home / fallback
