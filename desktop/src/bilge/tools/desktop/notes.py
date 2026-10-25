"""Notes in Bilge's notes folder: taking one ("not al: …"), adding to one ("alışveriş notuma süt ekle"), listing them
("notlarım neler") and reading one ("alışveriş notunu oku"). What is read is the user's own text; only going on with
"devamını oku" may continue something else read just before, so that counts as someone else's text."""

from typing import Any

from bilge.brain.routing import Rule, rule
from bilge.core.language import AssistantLanguage
from bilge.core.notes import note_index, note_request
from bilge.core.notes.note_index import NoteEntry
from bilge.core.text import folded
from bilge.tools.base import Risk, Tool, ToolError
from bilge.tools.desktop.common import obj, string_argument, text
from bilge.tools.notes_folder import NotesError, NotesFolder
from bilge.tools.reading import TextReading, continued

LISTED_NOTES = 30
NOTE_CHARACTERS = 3000
# The text to add is read out in the question; a long one is cut there so it stays listenable.
PREVIEW_CHARACTERS = 300
TITLE_FROM_BODY = 40

_TEXTS = {
    AssistantLanguage.TURKISH: {
        "create": "Yeni bir not oluşturur ('not al: …', 'alışveriş diye bir not oluştur').",
        "title": "Notun kısa başlığı",
        "body": "Notun içeriği, kullanıcının söylediği gibi; yoksa boş bırak",
        "append": "Mevcut bir notun sonuna metin ekler ('alışveriş notuma süt ekle').",
        "note": "Notun eksiz adı: 'alışveriş notuma' → 'alışveriş'",
        "text": "Eklenecek metin, kullanıcının söylediği gibi",
        "read": "Bir notu arar ve okur; konu söylenmezse en son notu okur. Notların listesini de söyler "
        "('notlarım neler', 'alışveriş notunu oku').",
        "query": "Aranan notun adı ya da içindeki bir kelime; en son not isteniyorsa boş bırak",
        "list": "Notların listesi isteniyorsa true",
        "created": "'{title}' başlıklı notu oluşturdum.",
        "nothing": "Notta ne yazmamı istediğini anlayamadım.",
        "no_text": "Nota ne eklememi istediğini anlayamadım.",
        "no_note": "'{note}' adında bir not bulamadım.",
        "question": "'{note}' notunun sonuna şunu ekleyeyim mi: {text}",
        "appended": "'{note}' notuna ekledim.",
        "more": "… (devamı var)",
        "none": "Hiç not bulamadım.",
        "not_found": "'{query}' geçen bir not bulamadım.",
        "listed": "{count} notun var, en son düzenlenenler: {names}",
        "failed": "Not klasörüne ulaşamadım: {folder}",
    },
    AssistantLanguage.ENGLISH: {
        "create": "Creates a new note ('take a note: …', 'make a note called shopping').",
        "title": "A short title for the note",
        "body": "The note's text, as the user said it; leave empty if none",
        "append": "Adds text to the end of an existing note ('add milk to my shopping note').",
        "note": "The note's name: 'my shopping note' → 'shopping'",
        "text": "The text to add, as the user said it",
        "read": "Finds a note and reads it; reads the latest note when none is named. Also lists the notes ('what "
        "notes do I have', 'read my shopping note').",
        "query": "The note's name or a word in it; leave empty for the latest note",
        "list": "True when the user wants the list of notes",
        "created": "I created the note '{title}'.",
        "nothing": "I didn't get what the note should say.",
        "no_text": "I didn't get what to add to the note.",
        "no_note": "I couldn't find a note called '{note}'.",
        "question": "Shall I add this to the end of the note '{note}': {text}",
        "appended": "I added it to '{note}'.",
        "more": "… (there is more)",
        "none": "I couldn't find any notes.",
        "not_found": "I couldn't find a note with '{query}' in it.",
        "listed": "You have {count} notes. The most recently changed: {names}",
        "failed": "I couldn't reach the notes folder: {folder}",
    },
}


class NoteTools:
    def __init__(self, notes: NotesFolder, language: AssistantLanguage, reading: TextReading | None = None):
        self.notes = notes
        self.language = language
        self.reading = reading
        self.texts = _TEXTS[language]
        # The note behind the last question, so the text goes to the note the user heard named.
        self._pending: dict[tuple[str, str], NoteEntry] = {}

    def _failed(self) -> ToolError:
        return ToolError(self.texts["failed"].format(folder=self.notes.folder))

    def _index(self) -> list[NoteEntry]:
        try:
            return self.notes.index()
        except NotesError as error:
            raise self._failed() from error

    def create(self, arguments: dict[str, Any]) -> str:
        title, body = string_argument(arguments, "title"), string_argument(arguments, "body")
        if not title and body:
            title = body.splitlines()[0][:TITLE_FROM_BODY].strip()
        if not title:
            raise ToolError(self.texts["nothing"])
        try:
            self.notes.create(title, body)
        except NotesError as error:
            raise self._failed() from error
        return self.texts["created"].format(title=title)

    def append_refine(self, arguments: dict[str, Any], command: str) -> dict[str, Any]:
        """The note and the words come from the sentence as said, when it says them plainly."""
        said = note_request.addition(command, self.language)
        return {"note": said.note, "text": said.text} if said else arguments

    def append_question(self, arguments: dict[str, Any]) -> str | None:
        self._pending.clear()
        note, added = string_argument(arguments, "note"), string_argument(arguments, "text")
        if not added:
            return None
        found = note_index.find(note, self._index()) if note else None
        if found is None:
            return None
        self._pending[(note, added)] = found
        preview = added if len(added) <= PREVIEW_CHARACTERS else added[:PREVIEW_CHARACTERS] + self.texts["more"]
        return self.texts["question"].format(note=found.name, text=preview)

    def append(self, arguments: dict[str, Any]) -> str:
        note, added = string_argument(arguments, "note"), string_argument(arguments, "text")
        if not added:
            raise ToolError(self.texts["no_text"])
        found = self._pending.pop((note, added), None)
        if found is None:
            # Nothing is written to a note the user didn't hear named in a question.
            raise ToolError(self.texts["no_note"].format(note=note))
        try:
            self.notes.append(found, added)
        except NotesError as error:
            raise self._failed() from error
        return self.texts["appended"].format(note=found.name)

    def read_refine(self, arguments: dict[str, Any], command: str) -> dict[str, Any]:
        # Whether to list is read from the words alone ("notlarım neler"), never guessed.
        listing = {**arguments, "list": note_request.asks_for_list(command, self.language)}
        return continued(self.reading, listing, command)

    def read(self, arguments: dict[str, Any]) -> str:
        if arguments.get("continue") and self.reading is not None:
            return self.reading.more()
        entries = self._index()
        if arguments.get("list"):
            latest = note_index.recent(entries, LISTED_NOTES)
            if not latest:
                return self.texts["none"]
            return self.texts["listed"].format(count=len(entries), names="; ".join(e.name for e in latest))
        query = string_argument(arguments, "query")
        found = self._find(query, entries)
        if found is None:
            raise ToolError(self.texts["not_found"].format(query=query) if query else self.texts["none"])
        try:
            content = self.notes.read(found)
        except NotesError as error:
            raise self._failed() from error
        if self.reading is None:
            return content[:NOTE_CHARACTERS]
        return self.reading.start(found.name, content, NOTE_CHARACTERS)

    def _find(self, query: str, entries: list[NoteEntry]) -> NoteEntry | None:
        """By name first, then the newest note with the words in it; the newest note when nothing is named."""
        latest = note_index.recent(entries, len(entries))
        if not query:
            return latest[0] if latest else None
        named = note_index.find(query, entries)
        if named is not None:
            return named
        wanted = folded(query)
        for entry in latest:
            try:
                if wanted in folded(self.notes.read(entry)):
                    return entry
            except NotesError:
                continue
        return None


def note_tools(notes: NotesFolder, language: AssistantLanguage, reading: TextReading | None = None) -> list[Tool]:
    tools = NoteTools(notes, language, reading)
    texts = tools.texts
    return [
        Tool(
            "createNote",
            texts["create"],
            run=tools.create,
            parameters=obj(["title"], title=text(texts["title"]), body=text(texts["body"])),
        ),
        Tool(
            "appendToNote",
            texts["append"],
            run=tools.append,
            parameters=obj(["note", "text"], note=text(texts["note"]), text=text(texts["text"])),
            risk=Risk.CONFIRM,
            confirmation=tools.append_question,
            refine=tools.append_refine,
        ),
        Tool(
            "readNotes",
            texts["read"],
            run=tools.read,
            parameters=obj(query=text(texts["query"]), list={"type": "boolean", "description": texts["list"]}),
            refine=tools.read_refine,
            untrusted_output=lambda arguments: bool(arguments.get("continue")),
        ),
    ]


def note_rules(language: AssistantLanguage) -> list[Rule]:
    """Plain requests go straight to the tool, with the user's own words."""

    def addition(command: str) -> dict[str, str]:
        said = note_request.addition(command, language)
        return {"note": said.note, "text": said.text} if said else {}

    return [
        rule("appendToNote", lambda command: note_request.addition(command, language) is not None, addition),
        rule("readNotes", lambda command: note_request.asks_for_list(command, language), lambda _: {"list": True}),
    ]
