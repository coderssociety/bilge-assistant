from types import SimpleNamespace

import psutil
import pytest

from bilge.core.language import AssistantLanguage
from bilge.desktop.linux.system import LinuxNetwork
from bilge.desktop.process import Completed, DesktopError
from bilge.desktop.windows.system import WindowsNetwork
from bilge.tools.desktop import system

from ..desktop.fakes import FakeRunner

TR = AssistantLanguage.TURKISH


class Network:
    def __init__(self, enabled, name):
        self.enabled, self.name = enabled, name

    def wifi_enabled(self):
        return self.enabled

    def wifi_name(self):
        return self.name


class Folders:
    def home(self):
        return "/"


def test_network_info_names_the_wifi_network(monkeypatch):
    monkeypatch.setattr(system, "local_ipv4", lambda: "192.168.1.20")
    tool = system.system_info_tool(Network(True, "Ev Ağı"), Folders(), TR)
    assert tool.run({"topic": "network"}) == "Wi-Fi açık, 'Ev Ağı' ağına bağlı. Yerel IP adresin 192.168.1.20."
    assert tool.reads_untrusted({"topic": "network"}) and not tool.reads_untrusted({"topic": "disk"})
    tool = system.system_info_tool(Network(False, None), Folders(), TR)
    assert tool.run({"topic": "network"}).startswith("Wi-Fi kapalı.")


def test_battery_time_left_only_when_asked():
    def tool(secsleft, plugged=False):
        battery = SimpleNamespace(percent=54, power_plugged=plugged, secsleft=secsleft)
        return system.battery_tool(TR, read=lambda: battery)

    assert tool(7800).run({}) == "Pil yüzde 54, pilden çalışıyor."
    assert tool(7800).run({"timeLeft": True}) == "Pil yüzde 54, pilden çalışıyor. Yaklaşık 2 saat 10 dakika daha yeter."
    assert tool(psutil.POWER_TIME_UNKNOWN).run({"timeLeft": True}).endswith("henüz hesaplanamadı.")
    assert tool(psutil.POWER_TIME_UNLIMITED, plugged=True).run({"timeLeft": True}) == "Pil yüzde 54, şarj oluyor."


def test_linux_wifi_name_from_nmcli_or_iwgetid():
    runner = FakeRunner({"nmcli"}, {"nmcli -t": "no:Komşu\nyes:Kafe\\:2\n"})
    assert LinuxNetwork(runner).wifi_name() == "Kafe:2"
    runner = FakeRunner({"nmcli"}, {"nmcli -t": "no:Komşu\n"})
    assert LinuxNetwork(runner).wifi_name() is None
    runner = FakeRunner({"iwgetid"}, {"iwgetid": "Ev\n"})
    assert LinuxNetwork(runner).wifi_name() == "Ev"


def test_windows_wifi_name_from_netsh():
    output = (
        "    Ad                     : Wi-Fi\n    SSID                   : Ev Ağı\n    BSSID                  : aa:bb\n"
    )
    runner = FakeRunner({"netsh"}, {"netsh wlan": output})
    assert WindowsNetwork(radios=lambda: [], runner=runner).wifi_name() == "Ev Ağı"
    runner = FakeRunner({"netsh"}, {"netsh wlan": Completed(1, "", "The Wireless AutoConfig Service is not running.")})
    assert WindowsNetwork(radios=lambda: [], runner=runner).wifi_name() is None


def test_a_winrt_runtime_error_reads_as_unknown_wifi():
    def broken():
        raise RuntimeError("Element not found")

    assert WindowsNetwork(radios=broken).wifi_enabled() is None


def test_a_winrt_runtime_error_while_switching_is_a_desktop_error():
    class Radio:
        async def set_state_async(self, state):
            raise RuntimeError("Access is denied")

    with pytest.raises(DesktopError):
        WindowsNetwork(radios=lambda: [Radio()]).set_wifi(False)
