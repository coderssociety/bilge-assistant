from datetime import datetime

import pytest

from bilge.brain.agent import Agent
from bilge.core.language import AssistantLanguage
from bilge.desktop.base import NowPlaying, PowerAction, RepeatMode
from bilge.desktop.process import DesktopError, MissingProgram, NotPossibleHere
from bilge.tools.base import Registry, ToolError
from bilge.tools.desktop import hardware, playback

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH


class FakeBrightness:
    def __init__(self, level=50, error=None):
        self.value, self.error = level, error

    def level(self):
        if self.error:
            raise self.error
        return self.value

    def set_level(self, level):
        if self.error:
            raise self.error
        self.value = level


def test_brightness_is_set_and_stepped_within_bounds():
    fake = FakeBrightness(95)
    tool = hardware.brightness_tool(fake, TR)
    assert tool.run({"action": "increase"}) == "Parlaklık yüzde 100."
    assert tool.run({"action": "decrease", "by": 30}) == "Parlaklık yüzde 70."
    assert tool.run({"action": "set", "level": 40}) == "Parlaklık yüzde 40."
    with pytest.raises(ToolError, match="Hedef parlaklık"):
        tool.run({"action": "set"})


def test_the_brightness_said_wins_over_the_models():
    tool = hardware.brightness_tool(FakeBrightness(), TR)
    assert tool.refine({"action": "set", "level": 5}, "parlaklığı yüzde 50 yap")["level"] == 50
    assert tool.refine({"action": "increase"}, "parlaklığı yüzde 20 artır") == {"action": "increase", "by": 20}


def test_brightness_failures_say_what_can_be_done():
    with pytest.raises(ToolError, match="monitörün kendi düğmelerini"):
        hardware.brightness_tool(FakeBrightness(error=NotPossibleHere("no wmi", "windows")), TR).run({"action": "set",
                                                                                                    "level": 5})  # fmt: skip
    with pytest.raises(ToolError, match="ddcutil"):
        hardware.brightness_tool(FakeBrightness(error=NotPossibleHere("none")), EN).run({"action": "increase"})
    with pytest.raises(ToolError, match="brightnessctl, ddcutil"):
        hardware.brightness_tool(FakeBrightness(error=MissingProgram("brightnessctl", "ddcutil")), EN).run(
            {"action": "increase"}
        )


class FakeDnd:
    def __init__(self, state=False, error=None):
        self.state, self.error = state, error

    def enabled(self):
        if self.error:
            raise self.error
        return self.state

    def set_enabled(self, on):
        if self.error:
            raise self.error
        self.state = on


class FakeSettings:
    def __init__(self):
        self.opened = []

    def open(self, pane):
        self.opened.append(pane)
        return True


def test_do_not_disturb_is_switched_and_read():
    fake = FakeDnd()
    tool = hardware.do_not_disturb_tool(fake, FakeSettings(), TR)
    assert tool.run({"action": "on"}) == "Rahatsız Etmeyin açık; bildirimler sessiz."
    assert fake.state is True
    assert tool.run({"action": "status"}) == "Rahatsız Etmeyin açık; bildirimler sessiz."
    assert tool.run({"action": "off"}) == "Rahatsız Etmeyin kapalı; bildirimler yeniden görünecek."


def test_windows_do_not_disturb_explains_the_shortcut_and_opens_the_settings():
    settings = FakeSettings()
    unsupported = NotPossibleHere("no api", "windows")
    tool = hardware.do_not_disturb_tool(FakeDnd(error=unsupported), settings, TR)
    assert "Win+N" in tool.run({"action": "on"})
    assert settings.opened == ["notifications"]
    assert "Win+N" in tool.run({"action": "status"})


def test_do_not_disturb_set_elsewhere_on_kde_or_unsupported():
    with pytest.raises(ToolError, match="başka bir yerden"):
        hardware.do_not_disturb_tool(FakeDnd(error=NotPossibleHere("held", "kde")), FakeSettings(), TR).run(
            {"action": "off"}
        )
    with pytest.raises(ToolError, match="notification icon"):
        hardware.do_not_disturb_tool(FakeDnd(error=NotPossibleHere("none")), FakeSettings(), EN).run({"action": "on"})
    assert (
        hardware.do_not_disturb_tool(FakeDnd(state=None), FakeSettings(), EN)
        .run({"action": "status"})
        .startswith("I couldn't read")
    )


class FakeBluetooth(FakeDnd):
    pass


def test_bluetooth_asks_only_before_turning_off():
    fake = FakeBluetooth(state=True)
    tool = hardware.bluetooth_tool(fake, TR)
    assert tool.question({"action": "off"}).endswith("Kapatayım mı?")
    assert tool.question({"action": "on"}) is None
    assert tool.question({"action": "status"}) is None
    assert tool.run({"action": "status"}) == "Bluetooth açık."
    assert tool.run({"action": "off"}) == "Bluetooth kapalı."
    with pytest.raises(ToolError, match="Bluetooth bulunamadı"):
        hardware.bluetooth_tool(FakeBluetooth(error=NotPossibleHere("none")), TR).run({"action": "on"})


class FakePower:
    def __init__(self, error=None):
        self.done, self.error = [], error

    def act(self, action):
        if self.error:
            raise self.error
        self.done.append(action)


def test_power_always_asks_and_names_the_action():
    fake = FakePower()
    tool = hardware.power_tool(fake, TR)
    assert (
        tool.question({"action": "restart"}) == "Kaydedilmemiş işler kaybolabilir. Bilgisayarı yeniden başlatayım mı?"
    )
    assert tool.question({"action": "logOut"}).endswith("Oturumu kapatayım mı?")
    assert tool.question({"action": "nonsense"}).endswith("Bilgisayarı kapatayım mı?")
    assert tool.run({"action": "shutDown"}) == "Bilgisayar kapatılıyor."
    assert fake.done == [PowerAction.SHUT_DOWN]
    with pytest.raises(ToolError, match="izin vermedi"):
        hardware.power_tool(FakePower(DesktopError("polkit")), TR).run({"action": "restart"})


class FakeMedia:
    def __init__(self, open_player=True, error=None):
        self.open_player, self.error, self.done = open_player, error, []

    def now_playing(self):
        return NowPlaying("Spotify", True, "Gülümse") if self.open_player else None

    def _act(self, *what):
        if self.error:
            raise self.error
        self.done.append(what)
        return "Spotify"

    def seek(self, seconds):
        return self._act("seek", seconds)

    def restart_track(self):
        return self._act("restart")

    def set_shuffle(self, on):
        return self._act("shuffle", on)

    def set_repeat(self, mode):
        return self._act("repeat", mode)


def test_playback_controls_reach_the_player():
    fake = FakeMedia()
    tool = playback.playback_tool(fake, TR)
    assert tool.run({"action": "seek", "seconds": 30}) == "Spotify 30 saniye ileri sarıldı."
    assert tool.run({"action": "seek", "seconds": -90}) == "Spotify 1 dakika 30 saniye geri sarıldı."
    assert tool.run({"action": "seek"}) == "Spotify 10 saniye ileri sarıldı."
    assert tool.run({"action": "restartTrack"}) == "Parça baştan başladı."
    assert tool.run({"action": "shuffleOff"}) == "Karışık çalma kapalı."
    assert tool.run({"action": "repeatTrack"}) == "Bu parça tekrarlanacak."
    assert fake.done[-3:] == [("restart",), ("shuffle", False), ("repeat", RepeatMode.TRACK)]
    english = playback.playback_tool(FakeMedia(), EN)
    assert english.run({"action": "seek", "seconds": 60}) == "Skipped 1 minute ahead in Spotify."


def test_playback_without_a_player_or_support():
    assert playback.playback_tool(FakeMedia(open_player=False), TR).run({"action": "seek"}) == (
        "Açık bir müzik çalar bulamadım."
    )
    with pytest.raises(ToolError, match="desteklemiyor"):
        playback.playback_tool(FakeMedia(error=NotPossibleHere("no shuffle")), TR).run({"action": "shuffleOn"})


class NoModel:
    def complete(self, messages, tools=None, **_):
        raise AssertionError("the fast path should have answered")


def test_fast_path_runs_the_new_tools_and_still_asks_before_power_actions():
    asked = []
    brightness, power = FakeBrightness(), FakePower()
    registry = Registry([hardware.brightness_tool(brightness, TR), hardware.power_tool(power, TR)])
    agent = Agent(NoModel(), registry, lambda question: asked.append(question) or False, TR,
                  clock=lambda: datetime(2026, 10, 25, 14, 30))  # fmt: skip
    assert agent.handle("parlaklığı yüzde elli yap").text == "Parlaklık yüzde 50."
    assert brightness.value == 50
    assert agent.handle("bilgisayarı kapat").text == "Tamam, yapmıyorum."
    assert asked == ["Kaydedilmemiş işler kaybolabilir. Bilgisayarı kapatayım mı?"]
    assert power.done == []
