"""The Linux desktop: freedesktop.org standards first (D-Bus, .desktop files, MPRIS), then the usual tools of GNOME,
KDE and the wlroots compositors."""

from bilge.desktop.base import Desktop
from bilge.desktop.linux import environment
from bilge.desktop.linux.apps import LinuxApps
from bilge.desktop.linux.audio import LinuxVolume
from bilge.desktop.linux.bluetooth import LinuxBluetooth
from bilge.desktop.linux.clipboard import LinuxClipboard
from bilge.desktop.linux.dbus import SessionBus
from bilge.desktop.linux.display import LinuxBrightness
from bilge.desktop.linux.keyboard import LinuxKeyboard
from bilge.desktop.linux.media import MprisMedia, installed_players
from bilge.desktop.linux.notifications import LinuxDoNotDisturb
from bilge.desktop.linux.power import LinuxPower
from bilge.desktop.linux.system import (
    LinuxFolders,
    LinuxNetwork,
    LinuxNotifier,
    LinuxOpener,
    LinuxScreenshots,
    LinuxSession,
    LinuxSettings,
)
from bilge.desktop.linux.windows import LinuxWindows
from bilge.desktop.music import MusicLauncher
from bilge.desktop.process import Runner


def build(languages: tuple[str, ...]) -> Desktop:
    runner = Runner()
    env = environment.current()
    bus = SessionBus()
    clipboard = LinuxClipboard(runner, env)
    apps = LinuxApps(runner, languages)
    media = MprisMedia(bus)
    opener = LinuxOpener(runner, bus)
    return Desktop(
        apps=apps,
        volume=LinuxVolume(runner),
        media=media,
        music=MusicLauncher(apps, opener, media, lambda: installed_players(apps, runner)),
        clipboard=clipboard,
        keyboard=LinuxKeyboard(runner, env, clipboard),
        windows=LinuxWindows(runner, env),
        session=LinuxSession(runner, env),
        network=LinuxNetwork(runner),
        screenshots=LinuxScreenshots(runner, env),
        settings=LinuxSettings(runner, env),
        opener=opener,
        notifier=LinuxNotifier(runner, bus),
        folders=LinuxFolders(),
        brightness=LinuxBrightness(runner, env, bus),
        do_not_disturb=LinuxDoNotDisturb(runner, env, bus),
        bluetooth=LinuxBluetooth(runner),
        power=LinuxPower(runner, env, bus),
    )
