from pathlib import Path

import pytest

from bilge.core.language import AssistantLanguage
from bilge.desktop.base import ScreenshotArea
from bilge.desktop.linux import environment
from bilge.desktop.linux.screenshot_portal import PortalUnavailable, screenshot_file
from bilge.desktop.linux.system import LinuxScreenshots
from bilge.desktop.process import Completed, DesktopError, MissingProgram
from bilge.tools.base import ToolError
from bilge.tools.desktop.system import screenshot_tool

from .fakes import FakeRunner

X11 = environment.current({"DISPLAY": ":0", "XDG_CURRENT_DESKTOP": "XFCE"})
GNOME_WAYLAND = environment.current({"WAYLAND_DISPLAY": "wayland-0", "XDG_CURRENT_DESKTOP": "ubuntu:GNOME"})
SWAY = environment.current({"WAYLAND_DISPLAY": "wayland-1", "XDG_CURRENT_DESKTOP": "sway"})


def no_portal(_):
    raise AssertionError("the portal must not be used")


def test_a_failing_screenshot_program_is_an_error_not_a_cancellation(tmp_path):
    runner = FakeRunner({"maim"}, {"maim": Completed(1, "", "Failed to open X display")})
    with pytest.raises(DesktopError, match="X display"):
        LinuxScreenshots(runner, X11, no_portal).capture(ScreenshotArea.WHOLE_SCREEN, tmp_path / "s.png")
    runner = FakeRunner({"maim"})
    with pytest.raises(DesktopError):
        LinuxScreenshots(runner, X11, no_portal).capture(ScreenshotArea.WHOLE_SCREEN, tmp_path / "s.png")


def test_a_cancelled_selection_is_a_cancellation(tmp_path):
    cancelled = Completed(1, "", "Selection was cancelled by keystroke or right-click.")
    runner = FakeRunner({"maim"}, {"maim": cancelled})
    assert not LinuxScreenshots(runner, X11, no_portal).capture(ScreenshotArea.SELECTION, tmp_path / "s.png")
    runner = FakeRunner({"grim", "slurp"}, {"slurp": Completed(1, "", "wl_display failed")})
    with pytest.raises(DesktopError, match="slurp"):
        LinuxScreenshots(runner, SWAY, no_portal).capture(ScreenshotArea.SELECTION, tmp_path / "s.png")


def test_gnome_wayland_without_gnome_screenshot_uses_the_portal(tmp_path):
    saved = tmp_path / "Screenshot from portal.png"
    saved.write_bytes(b"png")
    asked = []

    def portal(interactive):
        asked.append(interactive)
        return saved

    destination = tmp_path / "out.png"
    runner = FakeRunner({"grim"})
    assert LinuxScreenshots(runner, GNOME_WAYLAND, portal).capture(ScreenshotArea.SELECTION, destination)
    assert destination.read_bytes() == b"png" and not saved.exists()
    assert asked == [True]
    assert runner.commands == []
    assert not LinuxScreenshots(runner, GNOME_WAYLAND, lambda _: None).capture(ScreenshotArea.WHOLE_SCREEN,
                                                                                destination)  # fmt: skip


def test_no_portal_and_no_program_names_what_to_install(tmp_path):
    def portal(_):
        raise PortalUnavailable("no portal")

    with pytest.raises(MissingProgram) as error:
        LinuxScreenshots(FakeRunner(), GNOME_WAYLAND, portal).capture(ScreenshotArea.WHOLE_SCREEN, tmp_path / "s.png")
    assert "xdg-desktop-portal" in error.value.programs


def test_portal_answers_are_read():
    assert screenshot_file(0, {"uri": ("s", "file:///home/u/Resimler/Ekran%20g%C3%B6r%C3%BCnt%C3%BCs%C3%BC.png")}) == (
        Path("/home/u/Resimler/Ekran görüntüsü.png")
    )
    assert screenshot_file(1, {}) is None
    with pytest.raises(DesktopError):
        screenshot_file(2, {})
    with pytest.raises(DesktopError):
        screenshot_file(0, {"uri": ("s", "https://example.com/x.png")})


def test_the_tool_tells_a_failure_from_a_cancellation(tmp_path):
    class Screenshots:
        def __init__(self, result):
            self.result = result

        def capture(self, area, destination):
            if isinstance(self.result, Exception):
                raise self.result
            return self.result

    class Folders:
        def pictures(self):
            return tmp_path

    tr = AssistantLanguage.TURKISH
    tool = screenshot_tool(Screenshots(False), Folders(), tr)
    assert tool.run({"area": "selection"}) == "Seçim iptal edildi, ekran görüntüsü alınmadı."
    tool = screenshot_tool(Screenshots(DesktopError("maim exit 1")), Folders(), tr)
    with pytest.raises(ToolError, match="hata verdi"):
        tool.run({})
