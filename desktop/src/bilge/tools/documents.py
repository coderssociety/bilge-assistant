"""The text of a document (PDF, Word, Excel, PowerPoint, OpenDocument, plain text, web page) without opening it in
an app. Office files are zip archives of XML, read with the standard library."""

import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree

from bilge.core.web import html_text

READABLE = frozenset({"pdf", "txt", "md", "csv", "docx", "odt", "html", "htm", "rtf", "xlsx", "pptx"})
MAX_PDF_PAGES = 40
# A document's text part beyond this is not something to read aloud; it also keeps a zip bomb from filling memory.
MAX_XML_BYTES = 20_000_000
MAX_TEXT_BYTES = 2_000_000
_WORD = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
_ODF_TEXT = "{urn:oasis:names:tc:opendocument:xmlns:text:1.0}"
_SHEET = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
_DRAWING = "{http://schemas.openxmlformats.org/drawingml/2006/main}"
_NUMBERED_PART = re.compile(r"(\d+)\.xml$")


class UnreadableDocument(Exception):
    pass


def text_of(path: Path) -> str:
    kind = path.suffix.lower().lstrip(".")
    try:
        if kind == "pdf":
            return _pdf(path)
        if kind == "docx":
            return _paragraphs(_xml(path, "word/document.xml"), f"{_WORD}p", f"{_WORD}t")
        if kind == "odt":
            return _odt(_xml(path, "content.xml"))
        if kind == "xlsx":
            return _xlsx(path)
        if kind == "pptx":
            return "\n\n".join(
                _paragraphs(_xml(path, slide), f"{_DRAWING}p", f"{_DRAWING}t") for slide in _parts(path, "ppt/slides/")
            )
        if kind in ("html", "htm"):
            return html_text.extract(_read_text(path))
        if kind == "rtf":
            return _rtf(_read_text(path))
        return _read_text(path)
    except (OSError, ValueError, KeyError, zipfile.BadZipFile, ElementTree.ParseError) as error:
        raise UnreadableDocument(str(error)) from error


def _read_text(path: Path) -> str:
    with path.open("rb") as file:
        return file.read(MAX_TEXT_BYTES).decode("utf-8", errors="replace")


def _pdf(path: Path) -> str:
    from pypdf import PdfReader
    from pypdf.errors import PdfReadError

    try:
        reader = PdfReader(path)
        pages = reader.pages[:MAX_PDF_PAGES]
        return "\n".join(page.extract_text() or "" for page in pages)
    except PdfReadError as error:
        raise UnreadableDocument(str(error)) from error


def _xml(path: Path, member: str) -> ElementTree.Element:
    with zipfile.ZipFile(path) as archive:
        if archive.getinfo(member).file_size > MAX_XML_BYTES:
            raise UnreadableDocument("Document too large")
        data = archive.read(member)
    # Office documents never need a DTD; refusing one rules out entity expansion and external entities.
    if b"<!DOCTYPE" in data or b"<!ENTITY" in data:
        raise UnreadableDocument("Document declares entities")
    return ElementTree.fromstring(data)


def _parts(path: Path, folder: str) -> list[str]:
    """ "ppt/slides/slide1.xml", "slide2.xml", … in their own order, not the archive's."""
    with zipfile.ZipFile(path) as archive:
        names = [n for n in archive.namelist() if n.startswith(folder) and "/" not in n[len(folder) :]]
    numbered = [(int(found.group(1)), name) for name in names if (found := _NUMBERED_PART.search(name))]
    return [name for _, name in sorted(numbered)]


def _xlsx(path: Path) -> str:
    """Each sheet's rows, cells separated by tabs; text cells point into the shared strings."""
    try:
        shared = [
            "".join(node.text or "" for node in item.iter(f"{_SHEET}t"))
            for item in _xml(path, "xl/sharedStrings.xml").iter(f"{_SHEET}si")
        ]
    except KeyError:
        shared = []
    sheets = []
    for sheet in _parts(path, "xl/worksheets/"):
        rows = ["\t".join(_cell(cell, shared) for cell in row.iter(f"{_SHEET}c"))
                for row in _xml(path, sheet).iter(f"{_SHEET}row")]  # fmt: skip
        sheets.append("\n".join(row for row in rows if row.strip()))
    return "\n\n".join(sheets)


def _cell(cell: ElementTree.Element, shared: list[str]) -> str:
    kind = cell.get("t")
    if kind == "inlineStr":
        return "".join(node.text or "" for node in cell.iter(f"{_SHEET}t"))
    value = cell.findtext(f"{_SHEET}v") or ""
    if kind == "s" and value.isdigit() and int(value) < len(shared):
        return shared[int(value)]
    return value


def _paragraphs(root: ElementTree.Element, paragraph: str, run: str) -> str:
    return "\n".join("".join(node.text or "" for node in p.iter(run)) for p in root.iter(paragraph))


def _odt(root: ElementTree.Element) -> str:
    lines = []
    for element in root.iter():
        if element.tag in (f"{_ODF_TEXT}p", f"{_ODF_TEXT}h"):
            lines.append("".join(element.itertext()))
    return "\n".join(lines)


_RTF_CONTROL = re.compile(r"\\[a-zA-Z]+-?\d* ?|\\'[0-9a-fA-F]{2}|[{}]")


def _rtf(source: str) -> str:
    """Rough: control words and groups are dropped, which leaves the text of simple documents."""
    return _RTF_CONTROL.sub("", source.replace("\\par", "\n"))
