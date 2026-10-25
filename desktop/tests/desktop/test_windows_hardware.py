"""Windows brightness, Bluetooth, Do Not Disturb, power and playback control, with PowerShell and WinRT replaced."""

import asyncio
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest

from bilge.desktop.base import PowerAction, RepeatMode
from bilge.desktop.process import Completed, DesktopError, NotPossibleHere
from bilge.desktop.windows.hardware import WindowsBluetooth, WindowsBrightness, WindowsDoNotDisturb, WindowsPower
from bilge.desktop.windows.sound import WindowsMedia

from .fakes import FakeRunner


@pytest.fixture(autouse=True)
def event_loop_after_asyncio_run():
    yield
    # asyncio.run leaves no current loop behind, which later tests that ask for one expect.
    asyncio.set_event_loop(asyncio.new_event_loop())


def test_laptop_brightness_goes_through_wmi():
    runner = FakeRunner({"powershell"}, {"powershell": "70\r\n"})
    brightness = WindowsBrightness(runner)
    assert brightness.level() == 70
    brightness.set_level(140)
    script = runner.commands[-1][-1]
    assert "WmiSetBrightness" in script and "Brightness=100}" in script


def test_an_external_monitor_has_no_wmi_brightness():
    runner = FakeRunner({"powershell"}, {"powershell": Completed(1, "", "Not supported")})
    with pytest.raises(NotPossibleHere) as error:
        WindowsBrightness(runner).set_level(50)
    assert error.value.desktop == "windows"
    with pytest.raises(NotPossibleHere):
        WindowsBrightness(runner).level()


class Radio:
    def __init__(self, state=1, answer=1):
        self.state, self.answer, self.changes = state, answer, []

    async def set_state_async(self, state):
        self.changes.append(state)
        return self.answer


def test_bluetooth_radio_is_read_and_switched():
    radio = Radio(state=2)
    bluetooth = WindowsBluetooth(radios=lambda: [radio])
    assert bluetooth.enabled() is False
    bluetooth.set_enabled(True)
    assert radio.changes == [1]
    with pytest.raises(DesktopError):
        WindowsBluetooth(radios=lambda: [Radio(answer=2)]).set_enabled(False)


def test_no_bluetooth_radio_and_winrt_failures():
    with pytest.raises(NotPossibleHere):
        WindowsBluetooth(radios=lambda: []).enabled()

    def broken():
        raise RuntimeError("Access is denied")

    with pytest.raises(DesktopError):
        WindowsBluetooth(radios=broken).set_enabled(True)


def test_do_not_disturb_has_no_api_on_windows():
    with pytest.raises(NotPossibleHere) as error:
        WindowsDoNotDisturb().set_enabled(True)
    assert error.value.desktop == "windows"


def test_power_uses_shutdown():
    runner = FakeRunner({"shutdown"})
    power = WindowsPower(runner)
    for action in PowerAction:
        power.act(action)
    assert runner.commands == [["shutdown", "/r", "/t", "0"], ["shutdown", "/s", "/t", "0"], ["shutdown", "/l"]]


class Session:
    source_app_user_model_id = "Spotify.exe"

    def __init__(self, position=timedelta(seconds=50), end=timedelta(minutes=3), status=5, **controls):
        self.timeline = SimpleNamespace(position=position, start_time=timedelta(0), end_time=end,
                                        last_updated_time=None)  # fmt: skip
        self.status = status
        abilities = {"is_playback_position_enabled": True, "is_shuffle_enabled": True, "is_repeat_enabled": True}
        self.controls = SimpleNamespace(**{**abilities, **controls})
        self.calls = []

    def get_playback_info(self):
        return SimpleNamespace(playback_status=self.status, controls=self.controls)

    def get_timeline_properties(self):
        return self.timeline

    async def try_change_playback_position_async(self, ticks):
        self.calls.append(("position", ticks))
        return True

    async def try_change_shuffle_active_async(self, on):
        self.calls.append(("shuffle", on))
        return True

    async def try_change_auto_repeat_mode_async(self, mode):
        self.calls.append(("repeat", mode))
        return True


def test_seeking_stays_within_the_track():
    session = Session()
    media = WindowsMedia(sessions=lambda: [session])
    assert media.seek(30) == "Spotify"
    assert media.seek(-90) == "Spotify"
    assert media.seek(600) == "Spotify"
    assert session.calls == [("position", 800_000_000), ("position", 0), ("position", 1_800_000_000)]


def test_restart_shuffle_and_repeat():
    session = Session()
    media = WindowsMedia(sessions=lambda: [session])
    media.restart_track()
    media.set_shuffle(True)
    media.set_repeat(RepeatMode.ALL)
    assert session.calls == [("position", 0), ("shuffle", True), ("repeat", 2)]


def test_a_player_without_the_control_cannot_do_it():
    media = WindowsMedia(sessions=lambda: [Session(is_shuffle_enabled=False)])
    with pytest.raises(NotPossibleHere):
        media.set_shuffle(True)
    with pytest.raises(DesktopError):
        WindowsMedia(sessions=lambda: []).seek(10)


def test_a_playing_position_counts_the_time_since_the_player_reported_it():
    session = Session(status=4)
    session.timeline.last_updated_time = datetime.now(UTC) - timedelta(seconds=20)
    WindowsMedia(sessions=lambda: [session]).seek(10)
    assert abs(session.calls[-1][1] - 800_000_000) < 10_000_000
    # A timeline last reported an hour ago would land past the end; the reported position is used instead.
    session.timeline.last_updated_time = datetime.now(UTC) - timedelta(hours=1)
    WindowsMedia(sessions=lambda: [session]).seek(10)
    assert session.calls[-1] == ("position", 600_000_000)
