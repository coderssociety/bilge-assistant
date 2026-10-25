"""The Windows desktop: the Start menu, Core Audio, the system media controls, Unicode keyboard input, and Office
over COM."""

from bilge.desktop.base import Desktop
from bilge.desktop.music import MusicLauncher
from bilge.desktop.process import Runner
from bilge.desktop.windows.apps import WindowsApps
from bilge.desktop.windows.file_selection import ExplorerSelection
from bilge.desktop.windows.hardware import WindowsBluetooth, WindowsBrightness, WindowsDoNotDisturb, WindowsPower
from bilge.desktop.windows.input import WindowsClipboard, WindowsKeyboard
from bilge.desktop.windows.ocr import WindowsScreenText
from bilge.desktop.windows.sound import WindowsMedia, WindowsVolume, installed_players
from bilge.desktop.windows.system import (
    WindowsFolders,
    WindowsNetwork,
    WindowsNotifier,
    WindowsOpener,
    WindowsScreenshots,
    WindowsSession,
    WindowsSettings,
    WindowsWindowControl,
)


def build() -> Desktop:
    runner = Runner()
    opener = WindowsOpener(runner)
    apps = WindowsApps(runner)
    media = WindowsMedia()
    screenshots = WindowsScreenshots(opener)
    return Desktop(
        apps=apps,
        volume=WindowsVolume(),
        media=media,
        music=MusicLauncher(apps, opener, media, lambda: installed_players(apps)),
        clipboard=WindowsClipboard(),
        keyboard=WindowsKeyboard(),
        windows=WindowsWindowControl(),
        session=WindowsSession(),
        network=WindowsNetwork(runner=runner),
        screenshots=screenshots,
        screen_text=WindowsScreenText(screenshots),
        file_selection=ExplorerSelection(),
        settings=WindowsSettings(opener),
        opener=opener,
        notifier=WindowsNotifier(),
        folders=WindowsFolders(),
        brightness=WindowsBrightness(runner),
        do_not_disturb=WindowsDoNotDisturb(),
        bluetooth=WindowsBluetooth(),
        power=WindowsPower(runner),
    )
