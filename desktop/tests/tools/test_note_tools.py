import os

import pytest

from bilge.core.language import AssistantLanguage
from bilge.tools.base import Risk, ToolError
from bilge.tools.desktop.notes import note_rules, note_tools
from bilge.tools.notes_folder import NotesFolder, notes_folder
from bilge.tools.reading import TextReading

TR = AssistantLanguage.TURKISH


@pytest.fixture
def folder(tmp_path):
    return tmp_path / "Bilge Notlar"


def tools(folder, reading=None):
    create, append, read = note_tools(NotesFolder(folder), TR, reading)
    return create, append, read


def write(folder, name, content, modified):
    folder.mkdir(exist_ok=True)
    path = folder / name
    path.write_text(content, encoding="utf-8")
    os.utime(path, (modified, modified))
    return path


def test_a_new_note_is_a_markdown_file_named_after_its_title(folder):
    create, _, _ = tools(folder)
    assert create.risk is Risk.SAFE
    assert create.run({"title": "Alışveriş", "body": "süt, yumurta"}) == "'Alışveriş' başlıklı notu oluşturdum."
    assert create.run({"title": "Alışveriş"}) == "'Alışveriş' başlıklı notu oluşturdum."
    assert (folder / "Alışveriş.md").read_text(encoding="utf-8") == "# Alışveriş\n\nsüt, yumurta\n"
    assert (folder / "Alışveriş 2.md").read_text(encoding="utf-8") == "# Alışveriş\n"


def test_a_note_without_a_title_takes_its_first_words(folder):
    create, _, _ = tools(folder)
    create.run({"body": "Yarın saat 10'da dişçi"})
    assert (folder / "Yarın saat 10'da dişçi.md").exists()
    with pytest.raises(ToolError, match="anlayamadım"):
        create.run({"title": " ", "body": ""})


def test_adding_names_the_note_found_and_uses_the_words_said(folder):
    write(folder, "alisveris.md", "# Alışveriş\n\nekmek", 100)
    _, append, _ = tools(folder)
    arguments = append.refine({"note": "market", "text": "iki litre süt"}, "alışveriş notuma süt ekle")
    assert arguments == {"note": "alışveriş", "text": "süt"}
    assert append.risk is Risk.CONFIRM
    assert append.question(arguments) == "'Alışveriş' notunun sonuna şunu ekleyeyim mi: süt"
    assert append.run(arguments) == "'Alışveriş' notuna ekledim."
    assert (folder / "alisveris.md").read_text(encoding="utf-8") == "# Alışveriş\n\nekmek\nsüt\n"


def test_nothing_is_added_to_a_note_that_was_not_asked_about(folder):
    write(folder, "alisveris.md", "# Alışveriş\n", 100)
    _, append, _ = tools(folder)
    assert append.question({"note": "tatil", "text": "otel"}) is None
    with pytest.raises(ToolError, match="'tatil' adında bir not bulamadım"):
        append.run({"note": "tatil", "text": "otel"})
    with pytest.raises(ToolError):
        append.run({"note": "alışveriş", "text": "süt"})
    assert (folder / "alisveris.md").read_text(encoding="utf-8") == "# Alışveriş\n"


def test_a_long_addition_is_cut_in_the_question_but_written_whole(folder):
    write(folder, "a.md", "# Günlük\n", 100)
    _, append, _ = tools(folder)
    long_text = "kelime " * 80
    arguments = {"note": "günlük", "text": long_text.strip()}
    assert append.question(arguments).endswith("… (devamı var)")
    append.run(arguments)
    assert (folder / "a.md").read_text(encoding="utf-8").endswith(long_text.strip() + "\n")


def test_listing_comes_from_the_words_and_names_the_newest_first(folder):
    write(folder, "a.md", "# Alışveriş\n", 100)
    write(folder, "b.md", "kitaplar", 300)
    write(folder, "c.txt", "not a note", 400)
    _, _, read = tools(folder)
    assert read.refine({"list": False}, "notlarım neler")["list"] is True
    assert read.refine({"list": True, "query": "alışveriş"}, "alışveriş notunu oku")["list"] is False
    assert read.run({"list": True}) == "2 notun var, en son düzenlenenler: b; Alışveriş"


def test_reading_finds_a_note_by_name_then_by_content_then_the_newest(folder):
    write(folder, "a.md", "# Alışveriş\n\nsüt\nekmek", 100)
    write(folder, "b.md", "# Toplantı\n\nBütçe onaylandı", 200)
    _, _, read = tools(folder)
    assert read.run({"query": "alışverişin"}) == "Alışveriş\nsüt\nekmek"
    assert read.run({"query": "bütçe"}) == "Toplantı\nBütçe onaylandı"
    assert read.run({}) == "Toplantı\nBütçe onaylandı"
    with pytest.raises(ToolError, match="'tatil' geçen bir not bulamadım"):
        read.run({"query": "tatil"})


def test_notes_are_the_users_own_text_but_going_on_may_continue_something_else(folder):
    write(folder, "a.md", "# Uzun\n\n" + "Bir cümle daha. " * 400, 100)
    reading = TextReading(TR)
    _, _, read = tools(folder, reading)
    assert not read.reads_untrusted({"query": "uzun"})
    first = read.run({"query": "uzun"})
    assert first.startswith("Uzun\nBir cümle daha.") and first.endswith("(Devamı var.)")
    arguments = read.refine({"query": "uzun"}, "devamını oku")
    assert arguments["continue"] is True and read.reads_untrusted(arguments)
    assert read.run(arguments).startswith("Uzun, bölüm 2:")


def test_no_notes_folder_yet_means_no_notes(folder):
    _, _, read = tools(folder)
    assert read.run({"list": True}) == "Hiç not bulamadım."
    with pytest.raises(ToolError, match="Hiç not bulamadım"):
        read.run({})


def test_rules_take_plain_requests_with_the_users_words():
    add, listing = note_rules(TR)
    assert add("alışveriş notuma süt ekle").arguments == {"note": "alışveriş", "text": "süt"}
    assert add("süt almayı listeme ekle") is None
    assert listing("notlarım neler").arguments == {"list": True}
    assert listing("alışveriş notunu oku") is None


def test_the_folder_in_use_is_kept_when_the_language_changes(tmp_path):
    assert notes_folder(tmp_path, TR) == tmp_path / "Bilge Notlar"
    assert notes_folder(tmp_path, AssistantLanguage.ENGLISH) == tmp_path / "Bilge Notes"
    (tmp_path / "Bilge Notlar").mkdir()
    assert notes_folder(tmp_path, AssistantLanguage.ENGLISH) == tmp_path / "Bilge Notlar"
