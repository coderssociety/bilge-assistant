"""Locking, sleep, light and dark theme, Wi-Fi, settings pages, screenshots, notifications, folders and opening
things on Windows."""

import asyncio
import contextlib
import os
import re
import sys
import time
from pathlib import Path
from xml.sax.saxutils import escape

from bilge.desktop import image
from bilge.desktop.base import ScreenshotArea, WindowAction
from bilge.desktop.process import DesktopError, MissingProgram, Runner

_THEME_KEY = r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
# The selection is drawn by the Snipping Tool, which puts the result on the clipboard.
_SELECTION_SECONDS = 30
# Run from source, notifications go out under PowerShell's app id, which every Windows has; installed, under the id
# the installer gives Bilge's Start menu shortcut.
POWERSHELL_APP_ID = r"{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe"
BILGE_APP_ID = "CodersSociety.Bilge"


def notification_app_id() -> str:
    """Windows only shows notifications from an app id a Start menu shortcut carries; the installer makes one."""
    shortcut = Path(os.environ.get("APPDATA", "")) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Bilge.lnk"
    return BILGE_APP_ID if getattr(sys, "frozen", False) and shortcut.exists() else POWERSHELL_APP_ID


_FOLDERS = {
    "desktop": "B4BFCC3A-DB2C-424C-B029-7FE99A87C641",
    "downloads": "374DE290-123F-4565-9164-39C4925E467B",
    "documents": "FDD39AD0-238F-46AF-ADB4-6C85480369C7",
    "pictures": "33E28130-4E1E-4676-835A-98395C3BC3BB",
    "music": "4BD8D571-6D19-48D3-BE97-422220080E43",
    "videos": "18989B1D-99B5-455B-841C-AB7C74E4DDFC",
}
_SETTINGS_PAGES = {
    "wifi": "network-wifi", "bluetooth": "bluetooth", "network": "network-status", "sound": "sound",
    "displays": "display", "battery": "batterysaver", "notifications": "notifications", "focus": "quiethours",
    "privacy": "privacy", "keyboard": "typing", "general": "about", "wallpaper": "personalization-background",
    "softwareUpdate": "windowsupdate", "storage": "storagesense", "accessibility": "easeofaccess",
    "mouse": "mousetouchpad", "trackpad": "devices-touchpad",
}  # fmt: skip


def _api():
    from bilge.desktop.windows import win32

    return win32


class WindowsSession:
    def __init__(self, api=None, registry=None):
        self._api = api
        self._registry = registry

    @property
    def api(self):
        self._api = self._api or _api()
        return self._api

    @property
    def registry(self):
        if self._registry is None:
            import winreg

            self._registry = winreg
        return self._registry

    def lock(self) -> None:
        self.api.lock()

    def suspend(self) -> None:
        self.api.suspend()

    def dark_mode(self) -> bool | None:
        reg = self.registry
        try:
            with reg.OpenKey(reg.HKEY_CURRENT_USER, _THEME_KEY) as key:
                return reg.QueryValueEx(key, "AppsUseLightTheme")[0] == 0
        except OSError:
            return None

    def set_dark_mode(self, dark: bool) -> None:
        reg = self.registry
        try:
            with reg.CreateKey(reg.HKEY_CURRENT_USER, _THEME_KEY) as key:
                for name in ("AppsUseLightTheme", "SystemUsesLightTheme"):
                    reg.SetValueEx(key, name, 0, reg.REG_DWORD, 0 if dark else 1)
        except OSError as error:
            raise DesktopError(f"Could not change the theme: {error}") from error
        self.api.announce_setting_change("ImmersiveColorSet")


# The desktop itself and the taskbar are windows too, but not ones to minimize or close.
_SHELL_CLASSES = frozenset({"Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd"})


class WindowsWindowControl:
    def __init__(self, api=None):
        self._api = api

    @property
    def api(self):
        self._api = self._api or _api()
        return self._api

    def act(self, action: WindowAction) -> None:
        api = self.api
        window = api.foreground()
        if window is None or window.class_name in _SHELL_CLASSES:
            raise DesktopError("No window in front")
        if action is WindowAction.CLOSE:
            api.close(window)
        elif action is WindowAction.FULL_SCREEN:
            # Windows has no full-screen state of its own; apps that have one (browsers, Explorer, players) use F11.
            api.press(api.VK_F11)
        else:
            command = {WindowAction.MINIMIZE: api.SW_MINIMIZE, WindowAction.MAXIMIZE: api.SW_MAXIMIZE,
                       WindowAction.RESTORE: api.SW_RESTORE}[action]  # fmt: skip
            api.show(window, command)


# "    SSID                   : Ev Ağı"; the label stays English in every Windows language, and BSSID doesn't match.
_SSID_LINE = re.compile(r"^\s*SSID\s*:\s*(.+?)\s*$", re.MULTILINE)


async def system_radios(kind: str) -> list:
    """The radios of one kind ("WI_FI", "BLUETOOTH") behind the switches Windows shows in its quick settings; turning
    them on and off needs no administrator rights."""
    try:
        from winrt.windows.devices.radios import Radio, RadioKind
    except ImportError as error:
        raise MissingProgram("winrt-Windows.Devices.Radios") from error
    await Radio.request_access_async()
    wanted = getattr(RadioKind, kind)
    return [radio for radio in await Radio.get_radios_async() if radio.kind == wanted]


async def switch_radios(radios: list, enabled: bool, what: str) -> None:
    if not radios:
        raise DesktopError(f"No {what} radio")
    for radio in radios:
        # RadioState: 1 is on, 2 is off.
        result = await radio.set_state_async(1 if enabled else 2)
        if int(result) != 1:
            raise DesktopError(f"{what} refused the change: {int(result)}")


class WindowsNetwork:
    """Wi-Fi through the radio switch Windows shows in its quick settings."""

    def __init__(self, radios=None, runner: Runner | None = None):
        self._radios = radios
        self._runner = runner or Runner()

    async def _wifi(self):
        if self._radios is not None:
            return list(self._radios())
        return await system_radios("WI_FI")

    def wifi_enabled(self) -> bool | None:
        async def read():
            radios = await self._wifi()
            return int(radios[0].state) == 1 if radios else None

        try:
            return asyncio.run(read())
        except (DesktopError, OSError, RuntimeError):
            # WinRT reports a missing or refused radio as RuntimeError, which must not take systemInfo down.
            return None

    def wifi_name(self) -> str | None:
        done = self._runner.run(["netsh", "wlan", "show", "interfaces"])
        if not done.ok:
            return None
        found = _SSID_LINE.search(done.stdout)
        return found.group(1) if found else None

    def set_wifi(self, enabled: bool) -> None:
        async def change():
            await switch_radios(await self._wifi(), enabled, "Wi-Fi")

        try:
            asyncio.run(change())
        except (OSError, RuntimeError) as error:
            raise DesktopError(f"Wi-Fi: {error}") from error


class WindowsScreenshots:
    def __init__(self, opener, api=None):
        self._opener = opener
        self._api = api
        # The last capture's pixels, so copying it needs no PNG decoder.
        self._last: tuple[Path, image.Pixels] | None = None

    @property
    def api(self):
        self._api = self._api or _api()
        return self._api

    def capture(self, area: ScreenshotArea, destination: Path) -> bool:
        pixels = self.pixels(area)
        if pixels is None:
            return False
        destination.write_bytes(image.png(pixels))
        self._last = (destination, pixels)
        return True

    def pixels(self, area: ScreenshotArea) -> image.Pixels | None:
        """The capture in memory; None when the user gave up choosing an area."""
        api = self.api
        api.use_physical_pixels()
        if area is ScreenshotArea.SELECTION:
            return self._snip()
        window = api.foreground() if area is ScreenshotArea.FRONT_WINDOW else None
        rect = api.window_rect(window) if window is not None else api.screen_rect()
        return api.capture(*rect)

    def _snip(self) -> image.Pixels | None:
        api = self.api
        before = api.clipboard_sequence()
        self._opener.open("ms-screenclip:")
        deadline = time.monotonic() + _SELECTION_SECONDS
        while time.monotonic() < deadline:
            time.sleep(0.25)
            if api.clipboard_sequence() != before:
                data = api.clipboard_bitmap()
                if not data:
                    # Something other than a picture was copied meanwhile: the snip was given up.
                    return None
                try:
                    return image.from_dib(data)
                except ValueError as error:
                    raise DesktopError(f"Unreadable snip: {error}") from error
        return None

    def copy_image(self, picture: Path) -> None:
        if self._last is None or self._last[0] != picture:
            raise DesktopError("Only the screenshot just taken can be copied")
        pixels, self._last = self._last[1], None
        self.api.set_clipboard_bitmap(image.dib(pixels))


class WindowsSettings:
    def __init__(self, opener):
        self._opener = opener

    def open(self, pane: str) -> bool:
        page = _SETTINGS_PAGES.get(pane)
        self._opener.open(f"ms-settings:{page or ''}")
        return page is not None


class WindowsOpener:
    def __init__(self, runner: Runner, start=None):
        self._runner = runner
        self._start = start or getattr(os, "startfile", None)

    def open(self, target: str) -> None:
        if self._start is None:
            raise MissingProgram("os.startfile")
        try:
            self._start(target)
        except OSError as error:
            raise DesktopError(f"Could not open: {error}") from error

    def reveal(self, path: Path) -> None:
        # One argument, as Explorer expects it: "/select,C:\path\file".
        self._runner.spawn(["explorer.exe", f"/select,{path}"])


class WindowsNotifier:
    def __init__(self, app_id: str | None = None):
        self._app_id = app_id or notification_app_id()

    def notify(self, title: str, body: str) -> None:
        try:
            from winrt.windows.data.xml.dom import XmlDocument
            from winrt.windows.ui.notifications import ToastNotification, ToastNotificationManager
        except ImportError as error:
            raise MissingProgram("winrt-Windows.UI.Notifications") from error
        document = XmlDocument()
        try:
            document.load_xml(
                "<toast><visual><binding template='ToastGeneric'>"
                f"<text>{escape(_printable(title))}</text><text>{escape(_printable(body))}</text>"
                "</binding></visual></toast>"
            )
            # pywinrt names the overload that takes an app id on its own.
            notifier = ToastNotificationManager.create_toast_notifier_with_id(self._app_id)
            notifier.show(ToastNotification(document))
        except OSError as error:
            raise DesktopError(f"Notification: {error}") from error


def _printable(text: str) -> str:
    """XML can't carry control characters, which a reminder's text may hold."""
    return "".join(c if c.isprintable() or c == " " else " " for c in text)


class WindowsFolders:
    def __init__(self, api=None):
        self._api = api

    def _known(self, name: str, fallback: str) -> Path:
        self._api = self._api or _api()
        with contextlib.suppress(DesktopError):
            return self._api.known_folder(_FOLDERS[name])
        return Path.home() / fallback

    def home(self) -> Path:
        return Path.home()

    def desktop(self) -> Path:
        return self._known("desktop", "Desktop")

    def downloads(self) -> Path:
        return self._known("downloads", "Downloads")

    def documents(self) -> Path:
        return self._known("documents", "Documents")

    def pictures(self) -> Path:
        return self._known("pictures", "Pictures")

    def music(self) -> Path:
        return self._known("music", "Music")

    def videos(self) -> Path:
        return self._known("videos", "Videos")
