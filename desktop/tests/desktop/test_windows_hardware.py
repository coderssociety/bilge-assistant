"""Windows brightness, Bluetooth, Do Not Disturb, and power, with PowerShell and WinRT replaced."""

import asyncio

import pytest

from bilge.desktop.base import PowerAction
from bilge.desktop.process import Completed, DesktopError, NotPossibleHere
from bilge.desktop.windows.hardware import WindowsBluetooth, WindowsBrightness, WindowsDoNotDisturb, WindowsPower

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
