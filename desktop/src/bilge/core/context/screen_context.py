from dataclasses import dataclass
from urllib.parse import unquote, urlparse

from bilge.core.context.context_intent import Kind

# What GNOME's file managers put first on the clipboard when files are copied as text.
_FILE_LIST_MARKERS = frozenset({"x-special/nautilus-clipboard", "copy", "cut"})


@dataclass(frozen=True)
class ScreenContext:
    """What the user may be pointing at when they say "bu" or "şu": captured when the command is heard.
    URLs are kept as strings (file paths or web addresses)."""

    selected_text: str | None = None
    selected_files: tuple[str, ...] = ()
    page_url: str | None = None
    page_title: str | None = None
    # The file shown in the front window (Preview, TextEdit, Word…).
    document_url: str | None = None
    # What was copied earlier: "bu" falls back to it when nothing is selected.
    clipboard_text: str | None = None


@dataclass(frozen=True)
class Text:
    text: str
    # Copied earlier rather than selected now.
    copied: bool = False


@dataclass(frozen=True)
class Files:
    urls: tuple[str, ...]


@dataclass(frozen=True)
class Page:
    url: str
    title: str | None


@dataclass(frozen=True)
class Document:
    url: str


ContextItem = Text | Files | Page | Document


def resolve(wanted: Kind | None, screen: ScreenContext) -> ContextItem | None:
    """The named kind when the user said one ("bu dosya", "bu sayfa"); otherwise the most specific
    thing on screen: a selection (or else the clipboard's text), then selected files, then the page, then the open
    document."""
    trimmed = screen.selected_text.strip() if screen.selected_text is not None else ""
    copied = screen.clipboard_text.strip() if screen.clipboard_text is not None else ""
    if copied and names_files(copied):
        copied = ""
    text = Text(trimmed) if trimmed else Text(copied, copied=True) if copied else None
    files = Files(screen.selected_files) if screen.selected_files else None
    page = Page(screen.page_url, title=screen.page_title) if screen.page_url is not None else None
    document = Document(screen.document_url) if screen.document_url is not None else None
    match wanted:
        case Kind.TEXT:
            return text
        case Kind.PAGE:
            return page
        case Kind.FILE:
            if files is not None:
                return files
            return Files((screen.document_url,)) if screen.document_url is not None else None
        case Kind.DOCUMENT:
            return document or files
        case None:
            return text or files or page or document


def file_paths(uri_list: str) -> tuple[str, ...]:
    """The local files in a text/uri-list ("file:///home/u/Belgeler/rapor%20son.pdf"); comments and other
    addresses are left out."""
    paths = []
    for line in uri_list.splitlines():
        parsed = urlparse(line.strip())
        if parsed.scheme == "file" and parsed.netloc in ("", "localhost") and parsed.path:
            paths.append(unquote(parsed.path))
    return tuple(paths)


def names_files(text: str) -> bool:
    """Copied text that only lists files (a file manager's copy), which is not text to read out."""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    entries = [line for line in lines if line not in _FILE_LIST_MARKERS]
    return bool(entries) and all(line.startswith(("file://", "/")) for line in entries)
