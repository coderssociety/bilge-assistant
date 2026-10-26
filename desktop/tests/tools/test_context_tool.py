import pytest

from bilge.core.context.context_intent import Kind
from bilge.core.context.screen_context import Files, Text
from bilge.core.language import AssistantLanguage
from bilge.desktop.base import ScreenshotArea
from bilge.desktop.process import DesktopError, MissingProgram
from bilge.tools.base import ToolError
from bilge.tools.desktop.context import ContextReader, context_tool
from bilge.tools.reading import TextReading

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH


class FakeClipboard:
    def __init__(self, selected="", copied="", selection_error=None):
        self.selected = selected
        self.copied = copied
        self.selection_error = selection_error
        self.reads = []

    def selection(self):
        self.reads.append("selection")
        if self.selection_error:
            raise self.selection_error
        return self.selected

    def read(self):
        self.reads.append("clipboard")
        return self.copied

    def write(self, text):
        self.copied = text


class FakeFiles:
    def __init__(self, *paths, error=None):
        self.paths = paths
        self.error = error
        self.asked = 0

    def selected(self):
        self.asked += 1
        if self.error:
            raise self.error
        return self.paths


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


class FakeOpener:
    def __init__(self):
        self.opened = []

    def open(self, target):
        self.opened.append(target)

    def reveal(self, path):
        raise AssertionError("not used")


def make(clipboard, files=None, screen=None, language=TR, reading=None, opener=None):
    opener = opener or FakeOpener()
    reader = ContextReader(clipboard, files or FakeFiles())
    return context_tool(reader, screen or FakeScreen(), opener, language, reading), opener


def test_bu_is_the_selection_then_the_clipboard_then_the_selected_file(tmp_path):
    doc = tmp_path / "rapor.txt"
    doc.write_text("Rapor metni", encoding="utf-8")
    clipboard = FakeClipboard(selected="Seçili paragraf", copied="Kopyalanan")
    files = FakeFiles(doc)
    reader = ContextReader(clipboard, files)
    assert reader.item(None) == Text("Seçili paragraf")
    assert clipboard.reads == ["selection"] and files.asked == 0
    clipboard.selected = ""
    assert reader.item(None) == Text("Kopyalanan", copied=True)
    clipboard.copied = ""
    assert reader.item(None) == Files((str(doc),))
    assert reader.item(Kind.TEXT) is None


def test_a_named_file_skips_the_texts_and_an_unreadable_selection_is_skipped():
    clipboard = FakeClipboard(selected="metin", copied="pano", selection_error=DesktopError("console"))
    reader = ContextReader(clipboard, FakeFiles(error=DesktopError("no explorer")))
    assert reader.item(None) == Text("pano", copied=True)
    clipboard.reads.clear()
    assert reader.item(Kind.FILE) is None and clipboard.reads == []


def test_summarize_this_hands_the_text_over_as_untrusted_data():
    tool, _ = make(FakeClipboard(copied="Toplantı yarın 10'da."))
    assert tool.untrusted_output
    assert tool.run({"command": "bunu özetle"}) == "Panodaki metin:\nToplantı yarın 10'da."
    tool, _ = make(FakeClipboard(selected="Selected words"), language=EN)
    assert tool.run({"command": "translate this into Turkish"}) == "Selected text:\nSelected words"


def test_a_selected_document_is_read_and_long_text_goes_on_with_read_on(tmp_path):
    doc = tmp_path / "rapor.txt"
    doc.write_text("cümle " * 2000, encoding="utf-8")
    reading = TextReading(TR)
    tool, _ = make(FakeClipboard(), FakeFiles(tmp_path / "foto.png", doc), reading=reading)
    first = tool.run({"command": "bu dosyayı özetle"})
    assert first.startswith("Belge: rapor.txt:\n") and first.endswith("(Devamı var.)")
    assert tool.refine({"command": "x"}, "devamını oku")["continue"] is True
    assert tool.run({"continue": True}).startswith("Belge: rapor.txt, bölüm 2")
    with pytest.raises(ToolError, match="okuyabileceğim bir belge yok"):
        make(FakeClipboard(), FakeFiles(tmp_path / "foto.png"))[0].run({"command": "şu dosyayı oku"})


def test_this_page_is_read_from_the_front_window_when_nothing_else_is_there():
    screen = FakeScreen("  Fiyat:   1.250 TL \n\n\n Sepete ekle ")
    tool, _ = make(FakeClipboard(copied="eski pano"), screen=screen)
    assert tool.run({"command": "bu sayfayı özetle"}) == "Öndeki penceredeki yazı:\nFiyat: 1.250 TL\n\nSepete ekle"
    assert screen.areas == [ScreenshotArea.FRONT_WINDOW]
    with pytest.raises(ToolError, match="tesseract-ocr-tur"):
        make(FakeClipboard(), screen=FakeScreen(error=MissingProgram("tesseract")))[0].run({"command": "bunu özetle"})
    with pytest.raises(ToolError, match="Neyi kastettiğini"):
        make(FakeClipboard(), screen=FakeScreen("  "))[0].run({"command": "bunu açıkla"})


def test_open_this_opens_selected_documents_but_never_programs(tmp_path):
    doc, script = tmp_path / "rapor.pdf", tmp_path / "kur.sh"
    doc.write_bytes(b"%PDF")
    script.write_text("echo", encoding="utf-8")
    tool, opener = make(FakeClipboard(selected="metin"), FakeFiles(doc))
    assert tool.run({"command": "şu dosyayı aç"}) == "rapor.pdf açılıyor."
    assert opener.opened == [str(doc)]
    with pytest.raises(ToolError, match="programları sesle açmıyorum"):
        make(FakeClipboard(), FakeFiles(doc, script))[0].run({"command": "bunları aç"})
    with pytest.raises(ToolError, match="Neyi kastettiğini"):
        make(FakeClipboard(selected="metin"))[0].run({"command": "bunu aç"})


def test_requests_that_do_not_point_are_not_guessed():
    with pytest.raises(ToolError, match="anlayamadım"):
        make(FakeClipboard(selected="x"))[0].run({"command": "hava nasıl"})
    tool, _ = make(FakeClipboard())
    assert tool.refine({"command": "summarize"}, "bunu özetle") == {"command": "bunu özetle"}
