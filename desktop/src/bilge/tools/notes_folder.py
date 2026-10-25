"""The user's notes: one Markdown file per note in a "Bilge Notlar" folder inside Documents, readable and editable in
any text editor. A note's name is its "# heading", or the file name when it has none."""

from pathlib import Path

from bilge.core.language import AssistantLanguage
from bilge.core.notes import note_index
from bilge.core.notes.note_index import NoteEntry

FOLDER_NAMES = {AssistantLanguage.TURKISH: "Bilge Notlar", AssistantLanguage.ENGLISH: "Bilge Notes"}
# Larger files are not notes someone wants read aloud, and reading them whole would be slow.
MAX_NOTE_BYTES = 1_000_000


class NotesError(Exception):
    """The folder or a note couldn't be read or written."""


def notes_folder(documents: Path, language: AssistantLanguage) -> Path:
    """The folder already in use under either name, so switching languages keeps the same notes."""
    for name in (FOLDER_NAMES[language], *FOLDER_NAMES.values()):
        if (documents / name).is_dir():
            return documents / name
    return documents / FOLDER_NAMES[language]


class NotesFolder:
    def __init__(self, folder: Path):
        self.folder = folder

    def index(self) -> list[NoteEntry]:
        try:
            files = [path for path in self.folder.glob("*.md") if path.is_file()]
        except OSError as error:
            raise NotesError(str(error)) from error
        entries = []
        for path in files:
            try:
                with path.open(encoding="utf-8", errors="replace") as file:
                    first = file.readline()
                modified = path.stat().st_mtime
            except OSError:
                continue
            entries.append(NoteEntry(note_index.title(first, path.stem), path, modified))
        return entries

    def read(self, entry: NoteEntry) -> str:
        """The note with its heading as a plain first line."""
        try:
            if entry.path.stat().st_size > MAX_NOTE_BYTES:
                raise NotesError(f"{entry.path} is too large")
            content = entry.path.read_text(encoding="utf-8", errors="replace").strip()
        except OSError as error:
            raise NotesError(str(error)) from error
        first, _, rest = content.partition("\n")
        if first.lstrip().startswith("#"):
            return f"{entry.name}\n{rest.strip()}".strip()
        return f"{entry.name}\n{content}"

    def create(self, title: str, body: str) -> NoteEntry:
        try:
            self.folder.mkdir(parents=True, exist_ok=True)
            taken = {path.name for path in self.folder.iterdir()}
            path = self.folder / note_index.file_name(title, taken)
            content = f"# {title}\n\n{body}\n" if body else f"# {title}\n"
            # "x": never overwrite a file that appeared in the meantime.
            with path.open("x", encoding="utf-8") as file:
                file.write(content)
            return NoteEntry(title, path, path.stat().st_mtime)
        except OSError as error:
            raise NotesError(str(error)) from error

    def append(self, entry: NoteEntry, text: str) -> None:
        """Adds the text as a new line at the end."""
        try:
            ends_open = False
            with entry.path.open("rb") as file:
                if file.seek(0, 2) > 0:
                    file.seek(-1, 2)
                    ends_open = file.read(1) != b"\n"
            with entry.path.open("a", encoding="utf-8") as file:
                file.write(("\n" if ends_open else "") + text + "\n")
        except OSError as error:
            raise NotesError(str(error)) from error
