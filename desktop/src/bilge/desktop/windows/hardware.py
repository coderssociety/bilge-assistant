"""Screen brightness, Bluetooth, Do Not Disturb, and restarting, shutting down or signing out on Windows."""

import asyncio

from bilge.desktop.base import PowerAction
from bilge.desktop.process import DesktopError, NotPossibleHere, Runner
from bilge.desktop.windows.system import switch_radios, system_radios

_POWERSHELL = ["powershell", "-NoProfile", "-NonInteractive", "-Command"]
# WMI reaches built-in panels only; external monitors are dimmed with their own buttons.
_READ_BRIGHTNESS = (
    "(Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -ErrorAction Stop "
    "| Select-Object -First 1).CurrentBrightness"
)
_SET_BRIGHTNESS = (
    "Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop "
    "| Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{{Timeout=1; Brightness={level}}} -ErrorAction Stop "
    "| Out-Null"
)
_POWER = {
    PowerAction.RESTART: ["shutdown", "/r", "/t", "0"],
    PowerAction.SHUT_DOWN: ["shutdown", "/s", "/t", "0"],
    PowerAction.LOG_OUT: ["shutdown", "/l"],
}


class WindowsBrightness:
    def __init__(self, runner: Runner):
        self._runner = runner

    def level(self) -> int:
        done = self._runner.run([*_POWERSHELL, _READ_BRIGHTNESS])
        if not done.ok or not done.stdout.strip():
            raise NotPossibleHere(f"No WMI brightness: {done.stderr.strip()[:200]}", "windows")
        try:
            return int(done.stdout.strip().splitlines()[0])
        except ValueError as error:
            raise DesktopError(f"Unreadable brightness: {done.stdout[:100]}") from error

    def set_level(self, level: int) -> None:
        script = _SET_BRIGHTNESS.format(level=max(0, min(100, int(level))))
        done = self._runner.run([*_POWERSHELL, script])
        if not done.ok:
            raise NotPossibleHere(f"No WMI brightness: {done.stderr.strip()[:200]}", "windows")


class WindowsBluetooth:
    def __init__(self, radios=None):
        # For tests: a function returning the Bluetooth radios.
        self._radios = radios

    async def _bluetooth(self) -> list:
        if self._radios is not None:
            return list(self._radios())
        return await system_radios("BLUETOOTH")

    def _run(self, coroutine):
        try:
            return asyncio.run(coroutine)
        except (OSError, RuntimeError) as error:
            raise DesktopError(f"Bluetooth: {error}") from error

    def enabled(self) -> bool:
        async def read() -> bool:
            radios = await self._bluetooth()
            if not radios:
                raise NotPossibleHere("No Bluetooth radio")
            return any(int(radio.state) == 1 for radio in radios)

        return self._run(read())

    def set_enabled(self, on: bool) -> None:
        async def change() -> None:
            radios = await self._bluetooth()
            if not radios:
                raise NotPossibleHere("No Bluetooth radio")
            await switch_radios(radios, on, "Bluetooth")

        self._run(change())


class WindowsDoNotDisturb:
    """Focus assist and Do Not Disturb have no public API; the tool tells the user where the switch is."""

    def enabled(self) -> bool | None:
        raise NotPossibleHere("Windows has no public API for Do Not Disturb", "windows")

    def set_enabled(self, on: bool) -> None:
        raise NotPossibleHere("Windows has no public API for Do Not Disturb", "windows")


class WindowsPower:
    def __init__(self, runner: Runner):
        self._runner = runner

    def act(self, action: PowerAction) -> None:
        self._runner.check(_POWER[action])
