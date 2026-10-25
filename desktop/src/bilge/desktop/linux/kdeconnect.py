"""SMS through KDE Connect (or GSConnect, which provides the same kdeconnect-cli): the phone paired with this computer
sends the message."""

from bilge.desktop.base import PairedPhone
from bilge.desktop.process import DesktopError, MissingProgram, NotPossibleHere, Runner

PROGRAM = "kdeconnect-cli"
LIST_SECONDS = 10
SEND_SECONDS = 20


class KdeConnectMessages:
    def __init__(self, runner: Runner):
        self.runner = runner

    def reachable_phone(self) -> PairedPhone:
        if not self.runner.has(PROGRAM):
            raise MissingProgram(PROGRAM)
        # Paired and reachable now, one "<id> <name>" per line.
        listed = self.runner.check([PROGRAM, "--list-available", "--id-name-only"], timeout=LIST_SECONDS)
        for line in listed.splitlines():
            device, _, name = line.strip().partition(" ")
            if device:
                return PairedPhone(device, name.strip() or device)
        raise NotPossibleHere("No paired phone is reachable")

    def send(self, phone: PairedPhone, number: str, text: str) -> None:
        # "--option=value" keeps a message starting with "-" from being read as an option.
        argv = [PROGRAM, f"--send-sms={text}", f"--destination={number}", f"--device={phone.id}"]
        done = self.runner.run(argv, timeout=SEND_SECONDS)
        if not done.ok:
            raise DesktopError(f"{PROGRAM} could not send: {done.stderr.strip()[:300]}")
