import pytest

from bilge.core.language import AssistantLanguage
from bilge.desktop.linux import environment
from bilge.desktop.linux.system import LinuxSession, LinuxSettings
from bilge.desktop.linux.theme import ThemeDarkMode, variant
from bilge.desktop.process import Completed, MissingProgram, NotPossibleHere
from bilge.tools.base import ToolError
from bilge.tools.desktop.system import settings_tool, system_action_tool

from .fakes import FakeRunner

HYPRLAND = environment.current({"WAYLAND_DISPLAY": "wayland-1", "XDG_CURRENT_DESKTOP": "Hyprland"})
SWAY = environment.current({"WAYLAND_DISPLAY": "wayland-1", "XDG_CURRENT_DESKTOP": "sway"})
XFCE = environment.current({"DISPLAY": ":0", "XDG_CURRENT_DESKTOP": "XFCE"})
CINNAMON = environment.current({"DISPLAY": ":0", "XDG_CURRENT_DESKTOP": "X-Cinnamon"})
TR = AssistantLanguage.TURKISH


def test_hyprland_and_sway_start_their_locker_instead_of_trusting_loginctl():
    runner = FakeRunner({"loginctl", "hyprlock"})
    LinuxSession(runner, HYPRLAND).lock()
    assert runner.spawned == [["hyprlock"]] and runner.commands == []
    runner = FakeRunner({"loginctl", "swaylock"})
    LinuxSession(runner, SWAY).lock()
    assert runner.commands == [["swaylock", "-f"]]


def test_no_locker_on_a_tiling_compositor_is_said_honestly():
    with pytest.raises(MissingProgram) as error:
        LinuxSession(FakeRunner({"loginctl"}), HYPRLAND).lock()
    assert error.value.programs == ("hyprlock", "swaylock")


def test_a_failing_swaylock_is_an_error():
    runner = FakeRunner({"swaylock"}, {"swaylock": Completed(1, "", "Unable to connect to the compositor")})
    tool = system_action_tool(LinuxSession(runner, SWAY), TR)
    with pytest.raises(ToolError):
        tool.run({"action": "lockScreen"})


def test_theme_variants_are_only_chosen_when_installed():
    installed = {"Greybird", "Greybird-dark", "Mint-Y-Aqua", "Mint-Y-Dark-Aqua", "Adwaita"}.__contains__
    assert variant("Greybird", True, installed) == "Greybird-dark"
    assert variant("Greybird-dark", False, installed) == "Greybird"
    assert variant("Mint-Y-Aqua", True, installed) == "Mint-Y-Dark-Aqua"
    assert variant("Mint-Y-Dark-Aqua", False, installed) == "Mint-Y-Aqua"
    assert variant("Adwaita", True, installed) is None
    assert variant("Greybird-dark", True, installed) == "Greybird-dark"


def test_xfce_dark_mode_goes_through_xfconf(tmp_path):
    (tmp_path / "Greybird-dark").mkdir()
    runner = FakeRunner({"xfconf-query", "gsettings"}, {"xfconf-query": "Greybird\n"})
    session = LinuxSession(runner, XFCE, lambda desktop: ThemeDarkMode(runner, desktop, lambda: [tmp_path]))
    assert session.dark_mode() is False
    session.set_dark_mode(True)
    assert runner.commands[-1] == ["xfconf-query", "-c", "xsettings", "-p", "/Net/ThemeName", "-s", "Greybird-dark"]
    assert not any(argv[0] == "gsettings" for argv in runner.commands)


def test_cinnamon_dark_mode_sets_the_gtk_theme(tmp_path):
    (tmp_path / "Mint-Y-Dark-Aqua").mkdir()
    runner = FakeRunner({"gsettings"}, {"gsettings get": "'Mint-Y-Aqua'\n"})
    session = LinuxSession(runner, CINNAMON, lambda desktop: ThemeDarkMode(runner, desktop, lambda: [tmp_path]))
    session.set_dark_mode(True)
    assert runner.commands[-1] == ["gsettings", "set", "org.cinnamon.desktop.interface", "gtk-theme",
                                   "Mint-Y-Dark-Aqua"]  # fmt: skip


def test_a_theme_without_a_dark_version_is_reported(tmp_path):
    runner = FakeRunner({"xfconf-query"}, {"xfconf-query": "Adwaita\n"})
    session = LinuxSession(runner, XFCE, lambda desktop: ThemeDarkMode(runner, desktop, lambda: [tmp_path]))
    with pytest.raises(NotPossibleHere):
        session.set_dark_mode(True)
    with pytest.raises(ToolError, match="karanlık bir sürümü yüklü değil"):
        system_action_tool(session, TR).run({"action": "darkModeOn"})


def test_settings_on_xfce_and_cinnamon():
    runner = FakeRunner({"xfce4-settings-manager", "xfce4-display-settings", "gnome-control-center"})
    settings = LinuxSettings(runner, XFCE)
    assert settings.open("displays")
    assert not settings.open("privacy")
    assert runner.spawned == [["xfce4-display-settings"], ["xfce4-settings-manager"]]
    runner = FakeRunner({"cinnamon-settings"})
    assert LinuxSettings(runner, CINNAMON).open("wallpaper")
    assert runner.spawned == [["cinnamon-settings", "backgrounds"]]


def test_tiling_compositors_open_standalone_tools_or_say_there_is_no_settings_app():
    runner = FakeRunner({"pavucontrol", "gnome-control-center"})
    assert LinuxSettings(runner, HYPRLAND).open("sound")
    assert runner.spawned == [["pavucontrol"]]
    with pytest.raises(NotPossibleHere):
        LinuxSettings(runner, HYPRLAND).open("keyboard")
    with pytest.raises(ToolError, match="ayarlar uygulaması yok"):
        settings_tool(LinuxSettings(FakeRunner(), SWAY), TR).run({"pane": "displays"})
