import pytest

from bilge.core.language import AssistantLanguage
from bilge.desktop.base import ScreenshotArea
from bilge.desktop.process import DesktopError, MissingProgram, NotPossibleHere
from bilge.tools.base import ToolError
from bilge.tools.desktop.screen import SCREEN_CHARACTERS, read_screen_tool
from bilge.tools.reading import TextReading

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH


class FakeScreen:
    def __init__(self, text="", error=None):
        self.text = text
        self.error = error
        self.areas = []

    def read(self, area):
        self.areas.append(area)
        if self.error:
            raise self.error
        return self.text


def test_the_screen_text_is_untrusted_and_read_from_the_front_window_by_default():
    screen = FakeScreen("  Dosya   bulunamadı \n\n\n Tamam ")
    tool = read_screen_tool(screen, TR)
    assert tool.untrusted_output
    assert tool.run({}) == "Ekrandaki yazı:\nDosya bulunamadı\n\nTamam"
    tool.run({"scope": "wholeScreen"})
    assert screen.areas == [ScreenshotArea.FRONT_WINDOW, ScreenshotArea.WHOLE_SCREEN]


def test_a_long_screen_goes_on_with_read_on():
    reading = TextReading(TR)
    tool = read_screen_tool(FakeScreen("kelime " * 1000), TR, reading)
    first = tool.run({})
    assert first.endswith("(Devamı var.)") and len(first) < SCREEN_CHARACTERS + 100
    assert tool.refine({}, "devamını oku") == {"continue": True}
    assert tool.run({"continue": True}).startswith("Ekran, bölüm 2")


def test_nothing_readable_is_said():
    with pytest.raises(ToolError, match="okunabilir bir yazı"):
        read_screen_tool(FakeScreen(" \n "), TR).run({})


@pytest.mark.parametrize(
    ("error", "message"),
    [
        (MissingProgram("tesseract"), "sudo apt install tesseract-ocr tesseract-ocr-tur"),
        (MissingProgram("tesseract-ocr-tur", "tesseract-ocr-eng"), "tesseract-langpack-tur"),
        (NotPossibleHere("No OCR language installed", desktop="windows"), "dil paketini"),
        (MissingProgram("gnome-screenshot", "grim"), "gnome-screenshot, grim"),
        (DesktopError("broken"), "okuyamadım"),
    ],
)
def test_what_is_missing_is_named_with_how_to_get_it(error, message):
    with pytest.raises(ToolError, match=message):
        read_screen_tool(FakeScreen(error=error), TR).run({})


def test_english_install_hint():
    with pytest.raises(ToolError, match="Install it with"):
        read_screen_tool(FakeScreen(error=MissingProgram("tesseract")), EN).run({})
