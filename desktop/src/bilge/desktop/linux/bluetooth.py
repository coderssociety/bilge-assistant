"""The Bluetooth adapter through BlueZ's bluetoothctl, or the radio switch rfkill where only that is installed."""

from bilge.desktop.process import Completed, DesktopError, MissingProgram, NotPossibleHere, Runner

_NO_ADAPTER = "no default controller"
# bluetoothctl waits for the Bluetooth service when it isn't running, so it isn't given long.
_SECONDS = 10


class LinuxBluetooth:
    def __init__(self, runner: Runner):
        self._runner = runner

    def enabled(self) -> bool:
        if self._runner.has("bluetoothctl"):
            done = self._runner.run(["bluetoothctl", "show"], timeout=_SECONDS)
            _check_adapter(done)
            if not done.ok:
                raise DesktopError(f"bluetoothctl show failed: {done.stderr.strip()[:200]}")
            for line in done.stdout.splitlines():
                key, _, value = line.strip().partition(":")
                if key == "Powered":
                    return value.strip() == "yes"
            raise DesktopError("bluetoothctl show gave no power state")
        if self._runner.has("rfkill"):
            listing = self._runner.check(["rfkill", "list", "bluetooth"])
            if not listing.strip():
                raise NotPossibleHere("No Bluetooth adapter")
            return "blocked: yes" not in listing.lower()
        raise MissingProgram("bluetoothctl", "rfkill")

    def set_enabled(self, on: bool) -> None:
        has = self._runner.has
        if not has("bluetoothctl"):
            if not has("rfkill"):
                raise MissingProgram("bluetoothctl", "rfkill")
            self._runner.check(["rfkill", "unblock" if on else "block", "bluetooth"])
            return
        done = self._power(on)
        if _succeeded(done):
            return
        _check_adapter(done)
        # An adapter switched off with the radio switch refuses to power on until it is unblocked.
        if on and has("rfkill"):
            self._runner.check(["rfkill", "unblock", "bluetooth"])
            done = self._power(on)
            if _succeeded(done):
                return
        raise DesktopError(f"bluetoothctl power failed: {(done.stdout + done.stderr).strip()[:200]}")

    def _power(self, on: bool) -> Completed:
        return self._runner.run(["bluetoothctl", "power", "on" if on else "off"], timeout=_SECONDS)


def _succeeded(done: Completed) -> bool:
    """Older bluetoothctl versions exit with 0 even when the change failed."""
    output = (done.stdout + done.stderr).lower()
    return done.ok and "failed" not in output and _NO_ADAPTER not in output


def _check_adapter(done: Completed) -> None:
    if _NO_ADAPTER in (done.stdout + done.stderr).lower():
        raise NotPossibleHere("No Bluetooth adapter")
