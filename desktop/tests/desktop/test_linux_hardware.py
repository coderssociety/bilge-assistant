"""Brightness, Do Not Disturb, Bluetooth, power and playback control on Linux, with programs and D-Bus replaced."""

import pytest

from bilge.desktop.base import PowerAction, RepeatMode
from bilge.desktop.linux import environment
from bilge.desktop.linux.bluetooth import LinuxBluetooth
from bilge.desktop.linux.display import LinuxBrightness
from bilge.desktop.linux.media import MprisMedia, NoPlayer
from bilge.desktop.linux.notifications import LinuxDoNotDisturb
from bilge.desktop.linux.power import LinuxPower
from bilge.desktop.process import Completed, DesktopError, MissingProgram, NotPossibleHere

from .fakes import FakeRunner

GNOME = environment.current({"WAYLAND_DISPLAY": "wayland-0", "XDG_CURRENT_DESKTOP": "ubuntu:GNOME"})
KDE = environment.current({"WAYLAND_DISPLAY": "wayland-0", "XDG_CURRENT_DESKTOP": "KDE"})
XFCE = environment.current({"DISPLAY": ":0", "XDG_CURRENT_DESKTOP": "XFCE"})
SWAY = environment.current({"WAYLAND_DISPLAY": "wayland-1", "XDG_CURRENT_DESKTOP": "sway"})
CINNAMON = environment.current({"DISPLAY": ":0", "XDG_CURRENT_DESKTOP": "X-Cinnamon"})


class FakeBus:
    """Answers property reads from `properties` and method calls from `replies`, keyed by (name, member)."""

    def __init__(self, properties=None, replies=None, failing=()):
        self.properties = properties or {}
        self.replies = replies or {}
        self.failing = set(failing)
        self.calls = []

    def names(self):
        return [name for name, _ in self.properties]

    def call(self, name, path, interface, method, signature=None, *args):
        if (name, method) in self.failing:
            raise DesktopError("no such service")
        self.calls.append((name, interface, method, args))
        return self.replies.get((name, method), ())

    def get(self, name, path, interface, prop):
        if (name, prop) not in self.properties:
            raise DesktopError("no such property")
        return self.properties[(name, prop)]


GSD = "org.gnome.SettingsDaemon.Power"
SOLID = "org.kde.Solid.PowerManagement"
NOTIFICATIONS = "org.freedesktop.Notifications"


def test_gnome_brightness_goes_through_the_settings_daemon():
    bus = FakeBus({(GSD, "Brightness"): 40})
    brightness = LinuxBrightness(FakeRunner(), GNOME, bus)
    assert brightness.level() == 40
    brightness.set_level(130)
    assert bus.calls[-1] == (GSD, "org.freedesktop.DBus.Properties", "Set",
                             ("org.gnome.SettingsDaemon.Power.Screen", "Brightness", ("i", 100)))  # fmt: skip


def test_kde_brightness_is_scaled_to_its_maximum():
    bus = FakeBus(replies={(SOLID, "brightnessMax"): (1200,), (SOLID, "brightness"): (300,)})
    brightness = LinuxBrightness(FakeRunner(), KDE, bus)
    assert brightness.level() == 25
    brightness.set_level(50)
    assert bus.calls[-1][2:] == ("setBrightness", (600,))


def test_without_a_desktop_service_brightnessctl_sets_the_panel():
    runner = FakeRunner(
        {"brightnessctl"}, {"brightnessctl -m -c backlight info": "intel_backlight,backlight,400,40%,1000\n"}
    )
    brightness = LinuxBrightness(runner, SWAY, FakeBus())
    assert brightness.level() == 40
    brightness.set_level(55)
    assert runner.commands[-1] == ["brightnessctl", "-q", "-c", "backlight", "set", "55%"]


def test_gnome_without_a_panel_falls_back_to_ddcutil_for_an_external_monitor():
    runner = FakeRunner({"ddcutil"}, {"ddcutil getvcp": "VCP 10 C 30 200\n"})
    brightness = LinuxBrightness(runner, GNOME, FakeBus({(GSD, "Brightness"): -1}))
    assert brightness.level() == 15
    brightness.set_level(50)
    assert runner.commands[-1] == ["ddcutil", "setvcp", "10", "100"]


def test_brightness_says_what_to_install_or_that_nothing_can_be_dimmed():
    with pytest.raises(MissingProgram) as missing:
        LinuxBrightness(FakeRunner(), SWAY, FakeBus()).level()
    assert missing.value.programs == ("brightnessctl", "ddcutil")
    runner = FakeRunner({"brightnessctl"}, {"brightnessctl": Completed(1, "", "Failed to find a suitable device")})
    with pytest.raises(NotPossibleHere):
        LinuxBrightness(runner, SWAY, FakeBus()).set_level(50)


def test_gnome_and_cinnamon_do_not_disturb_hide_banners():
    runner = FakeRunner({"gsettings"}, {"gsettings get": "false\n"})
    dnd = LinuxDoNotDisturb(runner, GNOME, FakeBus())
    assert dnd.enabled() is True
    dnd.set_enabled(False)
    assert runner.commands[-1] == ["gsettings", "set", "org.gnome.desktop.notifications", "show-banners", "true"]
    runner = FakeRunner({"gsettings"})
    LinuxDoNotDisturb(runner, CINNAMON, FakeBus()).set_enabled(True)
    assert runner.commands[-1] == ["gsettings", "set", "org.cinnamon.desktop.notifications", "display-notifications",
                                   "false"]  # fmt: skip


def test_xfce_and_dunst_have_their_own_switch():
    runner = FakeRunner({"xfconf-query"}, {"xfconf-query": "true\n"})
    dnd = LinuxDoNotDisturb(runner, XFCE, FakeBus())
    assert dnd.enabled() is True
    dnd.set_enabled(False)
    assert runner.commands[-1] == ["xfconf-query", "-c", "xfce4-notifyd", "-p", "/do-not-disturb", "-n", "-t", "bool",
                                   "-s", "false"]  # fmt: skip
    runner = FakeRunner({"dunstctl"})
    LinuxDoNotDisturb(runner, SWAY, FakeBus()).set_enabled(True)
    assert runner.commands[-1] == ["dunstctl", "set-paused", "true"]


def test_kde_do_not_disturb_inhibits_and_hands_the_inhibition_back():
    bus = FakeBus({(NOTIFICATIONS, "Inhibited"): False}, {(NOTIFICATIONS, "Inhibit"): (7,)})
    dnd = LinuxDoNotDisturb(FakeRunner(), KDE, bus)
    dnd.set_enabled(True)
    dnd.set_enabled(True)
    dnd.set_enabled(False)
    assert [call[2:] for call in bus.calls] == [("Inhibit", ("bilge", "", {})), ("UnInhibit", (7,))]
    bus.properties[(NOTIFICATIONS, "Inhibited")] = True
    with pytest.raises(NotPossibleHere) as error:
        dnd.set_enabled(False)
    assert error.value.desktop == "kde"


def test_do_not_disturb_elsewhere_is_not_possible_or_names_the_program():
    with pytest.raises(NotPossibleHere):
        LinuxDoNotDisturb(FakeRunner(), SWAY, FakeBus()).set_enabled(True)
    with pytest.raises(MissingProgram):
        LinuxDoNotDisturb(FakeRunner(), GNOME, FakeBus()).set_enabled(True)
    assert LinuxDoNotDisturb(FakeRunner(), SWAY, FakeBus()).enabled() is None


SHOW = "Controller 00:1A:7D:DA:71:13 (public)\n\tName: laptop\n\tPowered: yes\n\tDiscoverable: no\n"


def test_bluetooth_state_and_switch_through_bluetoothctl():
    runner = FakeRunner(
        {"bluetoothctl"}, {"bluetoothctl show": SHOW, "bluetoothctl power": "Changing power off succeeded\n"}
    )
    bluetooth = LinuxBluetooth(runner)
    assert bluetooth.enabled() is True
    bluetooth.set_enabled(False)
    assert runner.commands[-1] == ["bluetoothctl", "power", "off"]


def test_a_blocked_adapter_is_unblocked_before_powering_on():
    blocked = Completed(1, "Failed to set power on: org.bluez.Error.Blocked\n", "")

    class Runner(FakeRunner):
        def run(self, argv, input=None, timeout=15, capture=True):
            done = super().run(argv, input, timeout, capture)
            unblocked = ["rfkill", "unblock", "bluetooth"] in self.commands
            return Completed(0, "Changing power on succeeded\n", "") if unblocked else done

    runner = Runner({"bluetoothctl", "rfkill"}, {"bluetoothctl power": blocked})
    LinuxBluetooth(runner).set_enabled(True)
    assert runner.commands == [["bluetoothctl", "power", "on"], ["rfkill", "unblock", "bluetooth"],
                               ["bluetoothctl", "power", "on"]]  # fmt: skip


def test_no_adapter_and_rfkill_fallback():
    runner = FakeRunner({"bluetoothctl"}, {"bluetoothctl": Completed(1, "No default controller available\n", "")})
    with pytest.raises(NotPossibleHere):
        LinuxBluetooth(runner).enabled()
    with pytest.raises(NotPossibleHere):
        LinuxBluetooth(runner).set_enabled(True)
    runner = FakeRunner({"rfkill"}, {"rfkill list": "0: hci0: Bluetooth\n\tSoft blocked: yes\n\tHard blocked: no\n"})
    assert LinuxBluetooth(runner).enabled() is False
    LinuxBluetooth(runner).set_enabled(True)
    assert runner.commands[-1] == ["rfkill", "unblock", "bluetooth"]
    with pytest.raises(MissingProgram):
        LinuxBluetooth(FakeRunner()).enabled()


def test_restart_and_shut_down_go_through_systemd():
    runner = FakeRunner({"systemctl", "loginctl"})
    power = LinuxPower(runner, GNOME, FakeBus(), session_id="3")
    power.act(PowerAction.RESTART)
    power.act(PowerAction.SHUT_DOWN)
    assert runner.commands == [["systemctl", "reboot"], ["systemctl", "poweroff"]]
    with pytest.raises(MissingProgram):
        LinuxPower(FakeRunner(), GNOME, FakeBus(), session_id="3").act(PowerAction.RESTART)


def test_logging_out_follows_the_desktop():
    runner = FakeRunner({"gnome-session-quit"})
    LinuxPower(runner, GNOME, FakeBus(), session_id="3").act(PowerAction.LOG_OUT)
    assert runner.commands == [["gnome-session-quit", "--logout", "--no-prompt"]]
    bus = FakeBus()
    LinuxPower(FakeRunner(), KDE, bus, session_id="3").act(PowerAction.LOG_OUT)
    assert bus.calls == [("org.kde.Shutdown", "org.kde.Shutdown", "logout", ())]
    runner = FakeRunner({"qdbus6"})
    LinuxPower(runner, KDE, FakeBus(failing={("org.kde.Shutdown", "logout")}), session_id="3").act(PowerAction.LOG_OUT)
    assert runner.commands == [["qdbus6", "org.kde.ksmserver", "/KSMServer", "logout", "0", "0", "0"]]
    runner = FakeRunner({"swaymsg"})
    LinuxPower(runner, SWAY, FakeBus(), session_id="3").act(PowerAction.LOG_OUT)
    assert runner.commands == [["swaymsg", "exit"]]


def test_logging_out_elsewhere_ends_the_logind_session():
    runner = FakeRunner({"loginctl"})
    LinuxPower(runner, environment.current({}), FakeBus(), session_id="c2").act(PowerAction.LOG_OUT)
    assert runner.commands == [["loginctl", "terminate-session", "c2"]]
    with pytest.raises(MissingProgram):
        LinuxPower(FakeRunner(), environment.current({}), FakeBus(), session_id="").act(PowerAction.LOG_OUT)


PLAYER = "org.mpris.MediaPlayer2.spotify"
PLAYER_INTERFACE = "org.mpris.MediaPlayer2.Player"


def playing(**properties):
    defaults = {"PlaybackStatus": "Playing", "Identity": "Spotify", "CanSeek": True}
    return FakeBus({(PLAYER, key): value for key, value in {**defaults, **properties}.items()})


def test_seeking_moves_by_microseconds_and_respects_players_that_cannot():
    bus = playing()
    assert MprisMedia(bus).seek(-30) == "Spotify"
    assert bus.calls[-1] == (PLAYER, PLAYER_INTERFACE, "Seek", (-30_000_000,))
    with pytest.raises(NotPossibleHere):
        MprisMedia(playing(CanSeek=False)).seek(10)
    with pytest.raises(NoPlayer):
        MprisMedia(FakeBus()).seek(10)


def test_restarting_a_track_sets_its_position_or_seeks_back_to_the_start():
    bus = playing(Metadata={"mpris:trackid": ("o", "/com/spotify/track/42")})
    MprisMedia(bus).restart_track()
    assert bus.calls[-1] == (PLAYER, PLAYER_INTERFACE, "SetPosition", ("/com/spotify/track/42", 0))
    bus = playing(Position=95_000_000)
    MprisMedia(bus).restart_track()
    assert bus.calls[-1] == (PLAYER, PLAYER_INTERFACE, "Seek", (-95_000_000,))


def test_shuffle_and_repeat_are_set_as_properties_where_the_player_has_them():
    bus = playing(Shuffle=False, LoopStatus="None")
    media = MprisMedia(bus)
    media.set_shuffle(True)
    media.set_repeat(RepeatMode.TRACK)
    assert [call[3] for call in bus.calls] == [(PLAYER_INTERFACE, "Shuffle", ("b", True)),
                                              (PLAYER_INTERFACE, "LoopStatus", ("s", "Track"))]  # fmt: skip
    with pytest.raises(NotPossibleHere):
        MprisMedia(playing()).set_repeat(RepeatMode.ALL)
