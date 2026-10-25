from types import SimpleNamespace

import pytest

from bilge.desktop import image
from bilge.desktop.base import ScreenshotArea
from bilge.desktop.linux.ocr import TesseractScreenText
from bilge.desktop.process import Completed, DesktopError, MissingProgram
from bilge.desktop.windows.ocr import WindowsScreenText
from bilge.desktop.windows.system import WindowsScreenshots

from .fakes import FakeRunner

LISTING = "List of available languages (3):\neng\nosd\ntur\n"


class FakeScreenshots:
    def __init__(self, taken=True):
        self.taken = taken
        self.areas = []
        self.files = []

    def capture(self, area, destination):
        self.areas.append(area)
        self.files.append(destination)
        if self.taken:
            destination.write_bytes(b"png")
        return self.taken


def test_tesseract_reads_a_temporary_screenshot_that_is_removed_afterwards():
    runner = FakeRunner({"tesseract"}, {"tesseract --list-langs": LISTING, "tesseract": "Kaydedilmemiş değişiklikler"})
    shots = FakeScreenshots()
    reader = TesseractScreenText(runner, shots)
    assert reader.read(ScreenshotArea.FRONT_WINDOW) == "Kaydedilmemiş değişiklikler"
    picture = shots.files[0]
    assert runner.commands[-1] == ["tesseract", str(picture), "stdout", "-l", "tur+eng"]
    assert not picture.exists() and not picture.parent.exists()
    reader.read(ScreenshotArea.WHOLE_SCREEN)
    assert runner.commands.count(["tesseract", "--list-langs"]) == 1
    assert shots.areas == [ScreenshotArea.FRONT_WINDOW, ScreenshotArea.WHOLE_SCREEN]


def test_a_cancelled_capture_reads_nothing():
    runner = FakeRunner({"tesseract"}, {"tesseract --list-langs": LISTING})
    assert TesseractScreenText(runner, FakeScreenshots(taken=False)).read(ScreenshotArea.FRONT_WINDOW) == ""
    assert runner.commands == [["tesseract", "--list-langs"]]


def test_missing_tesseract_or_its_languages_name_what_to_install():
    shots = FakeScreenshots()
    with pytest.raises(MissingProgram) as missing:
        TesseractScreenText(FakeRunner(), shots).read(ScreenshotArea.FRONT_WINDOW)
    assert missing.value.programs == ("tesseract",)
    runner = FakeRunner({"tesseract"}, {"tesseract --list-langs": "List of available languages (1):\nosd"})
    with pytest.raises(MissingProgram) as languages:
        TesseractScreenText(runner, shots).read(ScreenshotArea.FRONT_WINDOW)
    assert languages.value.programs == ("tesseract-ocr-tur", "tesseract-ocr-eng")
    assert shots.files == []


def test_a_failing_tesseract_is_an_error():
    runner = FakeRunner(
        {"tesseract"}, {"tesseract --list-langs": LISTING, "tesseract": Completed(1, "", "Error opening data file")}
    )
    with pytest.raises(DesktopError, match="tesseract failed"):
        TesseractScreenText(runner, FakeScreenshots()).read(ScreenshotArea.FRONT_WINDOW)


def test_windows_recognizes_the_capture_in_memory():
    pixels = image.Pixels(1, 1, b"\0\0\0\xff")
    shots = SimpleNamespace(pixels=lambda area: pixels if area is ScreenshotArea.WHOLE_SCREEN else None)
    seen = []
    reader = WindowsScreenText(shots, recognize=lambda p: seen.append(p) or "Merhaba")
    assert reader.read(ScreenshotArea.WHOLE_SCREEN) == "Merhaba" and seen == [pixels]
    assert reader.read(ScreenshotArea.FRONT_WINDOW) == ""


def test_windows_screenshots_capture_the_front_window_as_pixels():
    pixels = image.Pixels(2, 1, b"\1" * 8)
    window = SimpleNamespace(handle=1)
    api = SimpleNamespace(use_physical_pixels=lambda: None, foreground=lambda: window,
                          window_rect=lambda w: (10, 20, 2, 1), screen_rect=lambda: (0, 0, 9, 9),
                          capture=lambda *rect: pixels if rect == (10, 20, 2, 1) else None)  # fmt: skip
    assert WindowsScreenshots(opener=None, api=api).pixels(ScreenshotArea.FRONT_WINDOW) is pixels


def test_large_captures_are_shrunk_to_what_the_recognizer_takes():
    row = bytes(range(16))  # four pixels
    pixels = image.Pixels(4, 2, row + row)
    small = image.shrunk(pixels, 2)
    assert (small.width, small.height) == (2, 1)
    assert small.bgra == bytes(range(4)) + bytes(range(8, 12))
    assert image.shrunk(pixels, 4) is pixels
    odd = image.shrunk(image.Pixels(5, 1, bytes(20)), 4)
    assert (odd.width, odd.height) == (3, 1) and len(odd.bgra) == 12
