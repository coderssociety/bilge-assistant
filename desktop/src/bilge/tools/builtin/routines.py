"""Routines: commands Bilge runs on its own at a time of day ("her gece 21'de hava durumunu söyle"). They are kept in
a file, and run only while Bilge listens; a time missed while it was closed or the computer slept is skipped.

A routine runs with nobody there to answer a question, so its command never runs a step that would need a spoken
yes: the agent stops there and Bilge says the routine needs the user instead."""

import json
import logging
import os
import threading
import uuid
from collections.abc import Callable
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from bilge.brain.routing import Rule, rule
from bilge.core.language import AssistantLanguage
from bilge.core.routines import routine_choice, routine_request, routine_schedule
from bilge.core.routines.routine_schedule import Routine
from bilge.tools.base import Risk, Tool, ToolError
from bilge.tools.desktop.common import choice, int_argument, integer, obj, string_argument, text

log = logging.getLogger(__name__)

DAY_IDS = ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
MAX_ROUTINES = 50


class RoutineStoreError(Exception):
    pass


class RoutineStore:
    """Read on every use, so a routine deleted in the settings window is gone for the running assistant too."""

    def __init__(self, path: Path):
        self.path = path
        self._lock = threading.Lock()

    def load(self) -> list[Routine]:
        with self._lock:
            return routine_schedule.sorted_routines(self._read())

    def add(self, routine: Routine) -> None:
        with self._lock:
            routines = self._read()
            if len(routines) >= MAX_ROUTINES:
                raise RoutineLimitError(f"At most {MAX_ROUTINES} routines")
            self._write([*routines, routine])

    def remove(self, ids: set[str]) -> int:
        with self._lock:
            routines = self._read()
            kept = [routine for routine in routines if routine.id not in ids]
            if len(kept) != len(routines):
                self._write(kept)
            return len(routines) - len(kept)

    def _read(self) -> list[Routine]:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            return [_routine(item) for item in data["routines"]]
        except FileNotFoundError:
            return []
        except (OSError, ValueError, KeyError, TypeError) as error:
            # Starting empty would overwrite the user's routines on the next save.
            raise RoutineStoreError(f"Could not read the routines in {self.path}: {error}") from error

    def _write(self, routines: list[Routine]) -> None:
        data = {"routines": [{"id": r.id, "days": sorted(r.days), "hour": r.hour, "minute": r.minute,
                              "command": r.command} for r in routines]}  # fmt: skip
        try:
            self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            temporary = self.path.with_suffix(".tmp")
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8") as file:
                file.write(json.dumps(data, ensure_ascii=False))
            temporary.replace(self.path)
        except OSError as error:
            raise RoutineStoreError(f"Could not save the routines to {self.path}: {error}") from error


class RoutineLimitError(RoutineStoreError):
    pass


def _routine(item: dict[str, Any]) -> Routine:
    days = frozenset(int(day) for day in item["days"])
    hour, minute = int(item["hour"]), int(item["minute"])
    if not days or not days <= routine_schedule.EVERY_DAY or not (0 <= hour < 24 and 0 <= minute < 60):
        raise ValueError(f"Bad routine schedule: {item}")
    return Routine(str(item["id"]), days, hour, minute, str(item["command"]))


class RoutineService:
    """Watches the wall clock while Bilge listens and hands each routine that comes due to `run`."""

    CHECK_SECONDS = 15.0
    # A routine due longer ago than this (the computer was asleep) is skipped, not run late.
    GRACE = timedelta(minutes=10)

    def __init__(
        self, store: RoutineStore, run: Callable[[Routine], None], clock: Callable[[], datetime] = datetime.now
    ):
        self.store = store
        self._run = run
        self._clock = clock
        self._last: datetime | None = None
        self._stopped = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        if self._thread is not None:
            return
        # Times that passed while Bilge was closed or not listening are not caught up.
        self._last = self._clock()
        self._stopped = threading.Event()
        self._thread = threading.Thread(target=self._watch, args=(self._stopped,), name="bilge-routines", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stopped.set()
        self._thread = None

    def check(self) -> list[Routine]:
        """Runs the routines due since the last check; returns them."""
        now = self._clock()
        # The clock set back: nothing is due twice.
        since = self._last if self._last is not None and self._last <= now else now
        self._last = now
        try:
            routines = self.store.load()
        except RoutineStoreError:
            log.exception("Routines are not running")
            return []
        due = routine_schedule.due(routines, since, now, self.GRACE)
        for routine in due:
            log.info("Running the %02d:%02d routine", routine.hour, routine.minute)
            try:
                self._run(routine)
            except Exception:  # noqa: BLE001 - one failed routine must not stop the others
                log.exception("A routine failed to start")
        return due

    def seconds_to_next(self) -> float:
        now = self._clock()
        try:
            routines = self.store.load()
        except RoutineStoreError:
            return self.CHECK_SECONDS
        upcoming = [moment for r in routines if (moment := routine_schedule.next_occurrence(r, now)) is not None]
        if not upcoming:
            return self.CHECK_SECONDS
        return max(0.05, min(self.CHECK_SECONDS, (min(upcoming) - now).total_seconds()))

    def _watch(self, stopped: threading.Event) -> None:
        while not stopped.wait(self.seconds_to_next()):
            try:
                self.check()
            except Exception:  # noqa: BLE001 - an unforeseen error must not end routines for the rest of the run
                log.exception("Checking the routines crashed")


_TEXTS = {
    AssistantLanguage.TURKISH: {
        "add": "Bilge'nin her gün ya da seçilen günlerde belirli bir saatte kendiliğinden çalıştıracağı bir rutin kurar, ör. 'her gece 21'de hava durumunu söyle'. Komut, o saatte kullanıcı söylemiş gibi çalıştırılır.",
        "days": "Hangi günler: her gün için yedisi, hafta içi için pazartesi-cuma, hafta sonu için cumartesi ve pazar",
        "hour": "Saat, 24 saat biçiminde. 'akşam dokuz' → 21",
        "minute": "Dakika. 'yedi buçuk' → 30",
        "command": "O saatte çalıştırılacak komut, kullanıcının söylediği gibi, zaman olmadan: 'hava durumunu söyle'",
        "confirm": "{schedule} “{command}” rutinini kurayım mı?",
        "added": "Tamam, rutin kuruldu: {schedule} “{command}”.",
        "unclear": "Rutinin günlerini, saatini ya da ne yapacağını anlayamadım.",
        "nested": "Bir rutinin komutu başka bir rutin olamaz.",
        "manage": "Kurulu rutinleri listeler, birini (sabah/akşam gibi adıyla, ne yaptığıyla ya da sırasıyla) ya da hepsini siler.",
        "name": "Hangi rutin: 'akşam', 'hava durumu' gibi. Söylenmediyse boş bırak.",
        "index": "Listedeki sırası (1 ilki). Söylenmediyse boş bırak.",
        "none": "Kurulu rutin yok.",
        "list_one": "Bir rutin var: {items}.",
        "list": "{count} rutin var: {items}.",
        "item": "{schedule} “{command}”",
        "confirm_delete": "{item} rutinini sileyim mi?",
        "confirm_delete_all": "{count} rutinin hepsini sileyim mi: {items}?",
        "deleted_one": "Rutin silindi: {item}.",
        "deleted_all": "{count} rutin silindi.",
        "not_found": "Öyle bir rutin bulamadım. Kurulu olanlar: {items}.",
        "which": "Birden fazla rutin var: {items}. Hangisini sileyim?",
        "failed": "Rutinlere ulaşamadım; dosyaları okunamıyor ya da yazılamıyor.",
        "too_many": "En çok {count} rutin kurulabilir; önce birini sil.",
    },
    AssistantLanguage.ENGLISH: {
        "add": "Sets up a routine Bilge runs by itself at a time of day, every day or on chosen days, e.g. 'every night at 9 tell me the weather'. The command is run then as if the user had said it.",
        "days": "Which days: all seven for every day, monday-friday for weekdays, saturday and sunday for weekends",
        "hour": "The hour, 24-hour clock. '9 pm' → 21",
        "minute": "The minute. 'half past seven' → 30",
        "command": "The command to run then, as the user said it, without the time: 'tell me the weather'",
        "confirm": "Shall I set up this routine: {schedule}, “{command}”?",
        "added": "OK, routine set: {schedule}, “{command}”.",
        "unclear": "I didn't get the days, the time or what the routine should do.",
        "nested": "A routine's command can't be another routine.",
        "manage": "Lists the routines, or deletes one (by name such as morning/evening, by what it does, or by position) or all of them.",
        "name": "Which routine: 'evening', 'weather' and so on. Leave empty if not said.",
        "index": "Its position in the list (1 is the first). Leave empty if not said.",
        "none": "There are no routines.",
        "list_one": "There is one routine: {items}.",
        "list": "There are {count} routines: {items}.",
        "item": "{schedule}, “{command}”",
        "confirm_delete": "Shall I delete the routine {item}?",
        "confirm_delete_all": "Shall I delete all {count} routines: {items}?",
        "deleted_one": "Deleted the routine: {item}.",
        "deleted_all": "Deleted {count} routines.",
        "not_found": "I couldn't find that routine. These are set: {items}.",
        "which": "There are several routines: {items}. Which one shall I delete?",
        "failed": "I can't reach the routines; their file can't be read or written.",
        "too_many": "At most {count} routines can be set; delete one first.",
    },
}  # fmt: skip


def describe(routine: Routine, language: AssistantLanguage) -> str:
    schedule = routine_schedule.describe(routine.days, routine.hour, routine.minute, language)
    return _TEXTS[language]["item"].format(schedule=schedule, command=routine.command)


def _requested_days(arguments: dict[str, Any]) -> frozenset[int]:
    raw = arguments.get("days")
    if not isinstance(raw, list):
        return frozenset()
    return frozenset(DAY_IDS.index(day) for day in raw if day in DAY_IDS)


def routine_tools(store: RoutineStore, language: AssistantLanguage) -> list[Tool]:
    texts = _TEXTS[language]

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        # The schedule said is read from the words themselves; the model sometimes shifts hours.
        parsed = routine_request.parse(command, language)
        if parsed is None:
            return arguments
        days = [DAY_IDS[day] for day in sorted(parsed.days)]
        return {**arguments, "days": days, "hour": parsed.hour, "minute": parsed.minute, "command": parsed.command}

    def requested(arguments: dict[str, Any]) -> tuple[frozenset[int], int, int, str]:
        days = _requested_days(arguments)
        hour, minute = int_argument(arguments, "hour"), int_argument(arguments, "minute") or 0
        command = string_argument(arguments, "command")
        if not days or hour is None or not (0 <= hour < 24 and 0 <= minute < 60) or not command:
            raise ToolError(texts["unclear"])
        if len(command) > routine_request.MAX_COMMAND_CHARACTERS:
            raise ToolError(texts["unclear"])
        if routine_request.parse(command, language) is not None or routine_request.removal(command, language):
            raise ToolError(texts["nested"])
        return days, hour, minute, command

    def confirmation(arguments: dict[str, Any]) -> str | None:
        try:
            days, hour, minute, command = requested(arguments)
        except ToolError:
            # Nothing would be set up; running it says why.
            return None
        question = texts["confirm"].format(schedule=routine_schedule.describe(days, hour, minute, language),
                                           command=command)  # fmt: skip
        return question[0].upper() + question[1:]

    def add(arguments: dict[str, Any]) -> str:
        days, hour, minute, command = requested(arguments)
        try:
            store.add(Routine(uuid.uuid4().hex, days, hour, minute, command))
        except RoutineLimitError as error:
            raise ToolError(texts["too_many"].format(count=MAX_ROUTINES)) from error
        except RoutineStoreError as error:
            log.warning("%s", error)
            raise ToolError(texts["failed"]) from error
        schedule = routine_schedule.describe(days, hour, minute, language)
        return texts["added"].format(schedule=schedule, command=command)

    def listed(routines: list[Routine], numbered: bool = False) -> str:
        parts = [describe(routine, language) for routine in routines]
        return "; ".join(f"{i}) {part}" if numbered else part for i, part in enumerate(parts, 1))

    def delete(routines: list[Routine], arguments: dict[str, Any]) -> str:
        name, index = string_argument(arguments, "name"), int_argument(arguments, "index")
        picked = routine_choice.chosen(routines, name, index)
        if not picked:
            return texts["not_found"].format(items=listed(routines))
        if len(picked) > 1:
            # Nothing named one of several: asking beats deleting the wrong one.
            return texts["which"].format(items=listed(picked, numbered=True))
        store.remove({picked[0].id})
        return texts["deleted_one"].format(item=describe(picked[0], language))

    def deletion(arguments: dict[str, Any]) -> str | None:
        # A deleted routine is gone for good, and a stray word can pick one; the routine is read back first.
        action = string_argument(arguments, "action")
        if action not in ("delete", "deleteAll"):
            return None
        try:
            routines = store.load()
        except RoutineStoreError:
            return None
        if action == "deleteAll":
            question = texts["confirm_delete_all"].format(count=len(routines), items=listed(routines))
            return question if routines else None
        picked = routine_choice.chosen(routines, string_argument(arguments, "name"), int_argument(arguments, "index"))
        if len(picked) != 1:
            # Nothing or several fit: running it says so without deleting anything.
            return None
        question = texts["confirm_delete"].format(item=describe(picked[0], language))
        return question[0].upper() + question[1:]

    def manage(arguments: dict[str, Any]) -> str:
        action = string_argument(arguments, "action")
        try:
            routines = store.load()
            if not routines:
                return texts["none"]
            if action == "deleteAll":
                return texts["deleted_all"].format(count=store.remove({r.id for r in routines}))
            if action == "delete":
                return delete(routines, arguments)
            key = "list_one" if len(routines) == 1 else "list"
            return texts[key].format(count=len(routines), items=listed(routines))
        except RoutineStoreError as error:
            log.warning("%s", error)
            raise ToolError(texts["failed"]) from error

    add_parameters = obj(
        ["days", "hour", "command"],
        days={"type": "array", "items": choice(list(DAY_IDS), ""), "description": texts["days"]},
        hour=integer(texts["hour"], 0, 23), minute=integer(texts["minute"], 0, 59), command=text(texts["command"]),
    )  # fmt: skip
    manage_parameters = obj(
        ["action"], action=choice(["list", "delete", "deleteAll"], ""), name=text(texts["name"]),
        index=integer(texts["index"], 1, MAX_ROUTINES),
    )  # fmt: skip
    return [
        Tool("addRoutine", texts["add"], run=add, parameters=add_parameters, risk=Risk.CONFIRM,
             confirmation=confirmation, refine=refine),
        Tool("manageRoutines", texts["manage"], run=manage, parameters=manage_parameters, risk=Risk.CONFIRM,
             confirmation=deletion),
    ]  # fmt: skip


def routine_rules(language: AssistantLanguage) -> list[Rule]:
    """Routine requests are told apart by their wording, before other rules see the command they carry ("her sabah
    8'de günün özetini oku" is not a request for the summary now)."""

    def adding(command: str) -> dict[str, Any]:
        parsed = routine_request.parse(command, language)
        if parsed is None:
            return {}
        return {"days": [DAY_IDS[day] for day in sorted(parsed.days)], "hour": parsed.hour, "minute": parsed.minute,
                "command": parsed.command}  # fmt: skip

    def removing(command: str) -> dict[str, Any]:
        found = routine_request.removal(command, language)
        if found is None:
            return {"action": "list"}
        return {"action": "deleteAll"} if found.every else {"action": "delete", "name": found.name}

    return [
        rule("addRoutine", lambda command: routine_request.parse(command, language) is not None, adding),
        rule("manageRoutines", lambda command: routine_request.removal(command, language) is not None, removing),
        rule("manageRoutines", lambda command: routine_request.asks_for_list(command, language),
             lambda _: {"action": "list"}),
    ]  # fmt: skip
