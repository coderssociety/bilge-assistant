import pytest

from bilge.desktop.base import PairedPhone
from bilge.desktop.linux.kdeconnect import KdeConnectMessages
from bilge.desktop.process import Completed, DesktopError, MissingProgram, NotPossibleHere

from .fakes import FakeRunner


def test_the_first_reachable_paired_phone_is_used():
    runner = FakeRunner({"kdeconnect-cli"}, {"kdeconnect-cli --list-available": "a1b2 Pixel 7\nc3d4 Tablet\n"})
    assert KdeConnectMessages(runner).reachable_phone() == PairedPhone("a1b2", "Pixel 7")


def test_no_program_or_no_phone_is_told_apart():
    with pytest.raises(MissingProgram):
        KdeConnectMessages(FakeRunner()).reachable_phone()
    with pytest.raises(NotPossibleHere):
        KdeConnectMessages(FakeRunner({"kdeconnect-cli"})).reachable_phone()


def test_the_message_goes_as_one_argument_even_when_it_looks_like_an_option():
    runner = FakeRunner({"kdeconnect-cli"})
    KdeConnectMessages(runner).send(PairedPhone("a1b2", "Pixel 7"), "+905321234567", "--help; geliyorum")
    assert runner.commands == [
        ["kdeconnect-cli", "--send-sms=--help; geliyorum", "--destination=+905321234567", "--device=a1b2"]
    ]


def test_a_failed_send_is_an_error():
    runner = FakeRunner({"kdeconnect-cli"}, {"kdeconnect-cli": Completed(1, "", "Device not reachable")})
    with pytest.raises(DesktopError):
        KdeConnectMessages(runner).send(PairedPhone("a1b2", "Pixel 7"), "+905321234567", "geliyorum")
