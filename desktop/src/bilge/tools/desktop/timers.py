"""Timers and alarms. They live in Bilge, so they only go off while it is running; when one does, Bilge says so and
the desktop shows a notification. Pending ones are kept in a file, so a restart doesn't lose them."""

import json
import logging
import math
import os
import threading
import uuid
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from pathlib import Path
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.core.tools import english_time_parser, timer_choice, timer_phrase_parser, timer_schedule
from bilge.tools.base import Tool, ToolError
from bilge.tools.desktop.common import choice, int_argument, integer, obj, string_argument, text

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class ScheduledTimer:
    id: str
    fires_at: datetime
    label: str | None


class TimerService:
    """One thread watches the wall clock. A countdown per timer would run on the monotonic clock, which stops while
    the computer sleeps, so a 7:00 alarm set at night would go off late by however long the lid was closed."""

    # At most this late after the computer wakes up.
    CHECK_SECONDS = 15.0

    def __init__(
        self,
        announce: Callable[[str], None],
        language: AssistantLanguage,
        clock=datetime.now,
        store: Path | None = None,
    ):
        self._announce = announce
        self._language = language
        self._clock = clock
        self._store = store
        self._changed = threading.Condition()
        self._timers: dict[str, ScheduledTimer] = {}
        self._thread: threading.Thread | None = None

    @property
    def timers(self) -> list[ScheduledTimer]:
        with self._changed:
            return sorted(self._timers.values(), key=lambda t: t.fires_at)

    def schedule(self, fires_at: datetime, label: str | None, now: datetime | None = None) -> ScheduledTimer:
        timer = ScheduledTimer(uuid.uuid4().hex, fires_at, label)
        with self._changed:
            self._timers[timer.id] = timer
            self._start_watching()
            self._save()
            self._changed.notify()
        return timer

    def cancel(self, timer_id: str) -> bool:
        """False when it already went off."""
        with self._changed:
            found = self._timers.pop(timer_id, None) is not None
            if found:
                self._save()
                self._changed.notify()
        return found

    def cancel_all(self) -> int:
        with self._changed:
            count = len(self._timers)
            self._timers.clear()
            self._save()
            self._changed.notify()
        return count

    def restore(self) -> list[ScheduledTimer]:
        """Takes back the timers kept from the last run. Those whose time passed while Bilge was closed are dropped,
        returned and announced, so the user learns they were missed."""
        kept = self._load()
        now = self._clock()
        missed = sorted((t for t in kept if t.fires_at <= now), key=lambda t: t.fires_at)
        with self._changed:
            for timer in kept:
                if timer.fires_at > now:
                    self._timers[timer.id] = timer
            if self._timers:
                self._start_watching()
            self._save()
            self._changed.notify()
        if missed:
            log.info("Dropped %d timers that went off while Bilge was closed", len(missed))
            self._say(self._missed_message(missed))
        return missed

    def _start_watching(self) -> None:
        if self._thread is None:
            self._thread = threading.Thread(target=self._watch, name="bilge-timers", daemon=True)
            self._thread.start()

    def _load(self) -> list[ScheduledTimer]:
        if self._store is None:
            return []
        try:
            data = json.loads(self._store.read_text(encoding="utf-8"))
            return [ScheduledTimer(str(item["id"]), datetime.fromisoformat(item["fires_at"]), item.get("label") or None)
                    for item in data["timers"]]  # fmt: skip
        except FileNotFoundError:
            return []
        except (OSError, ValueError, KeyError, TypeError) as error:
            log.warning("Could not read the saved timers in %s: %s", self._store, error)
            return []

    def _save(self) -> None:
        """Called with the lock held. A timer that can't be saved still goes off; only a restart would lose it."""
        if self._store is None:
            return
        data = {"timers": [{"id": t.id, "fires_at": t.fires_at.isoformat(), "label": t.label}
                           for t in self._timers.values()]}  # fmt: skip
        try:
            self._store.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            temporary = self._store.with_suffix(".tmp")
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8") as file:
                file.write(json.dumps(data, ensure_ascii=False))
            temporary.replace(self._store)
        except OSError:
            log.exception("Could not save the timers to %s", self._store)

    def _watch(self) -> None:
        while True:
            with self._changed:
                now = self._clock()
                due = [t for t in self._timers.values() if t.fires_at <= now]
                for timer in due:
                    del self._timers[timer.id]
                if not due:
                    upcoming = min((t.fires_at for t in self._timers.values()), default=None)
                    wait = self.CHECK_SECONDS if upcoming is None else (upcoming - now).total_seconds()
                    self._changed.wait(max(0.05, min(wait, self.CHECK_SECONDS)))
                    continue
                self._save()
            for timer in sorted(due, key=lambda t: t.fires_at):
                self._fire(timer)

    def _fire(self, timer: ScheduledTimer) -> None:
        english = self._language is AssistantLanguage.ENGLISH
        if timer.label:
            message = f"Reminder: {timer.label}." if english else f"Hatırlatma: {timer.label}."
        else:
            message = "Your timer is done." if english else "Zamanlayıcı doldu."
        self._say(message)

    def _missed_message(self, missed: list[ScheduledTimer]) -> str:
        listed = ", ".join(f"{t.fires_at:%H:%M}" + (f" {t.label}" if t.label else "") for t in missed)
        if self._language is AssistantLanguage.ENGLISH:
            return f"These timers went off while Bilge was closed: {listed}."
        return f"Bilge kapalıyken şu zamanlayıcıların zamanı geçti: {listed}."

    def _say(self, message: str) -> None:
        try:
            self._announce(message)
        except Exception:  # noqa: BLE001 - one failed announcement must not stop the other timers
            log.exception("Announcing a timer failed")


class TimerAction(StrEnum):
    LIST = "list"
    CANCEL = "cancel"
    CANCEL_ALL = "cancelAll"
    REMAINING = "remaining"


_TEXTS = {
    AssistantLanguage.TURKISH: {
        "set": "Zamanlayıcı ya da alarm kurar. Süre için 'minutes'/'seconds', belirli bir saat için 'hour'/'minute' kullan.",
        "minutes": "Kaç dakika sonra (süre)",
        "seconds": "Kaç saniye sonra (süre)",
        "hour": "Belirli saat, 24 saat biçiminde. 'sabah yedi' → 7, 'akşam altı' → 18",
        "minute": "Belirli saatin dakikası. 'yedi buçuk' → 30",
        "label": "Bir-üç kelimeyle ne için olduğu, örn. 'çay'. Söylenmediyse boş bırak.",
        "unclear": "Süre ya da saat anlaşılamadı.",
        "today": "Tamam, saat {time} için kurdum.",
        "tomorrow": "Tamam, yarın saat {time} için kurdum.",
        "manage": "Bilge'de kurulu zamanlayıcı ve alarmları listeler, kalan süreyi söyler, birini (etiketi ya da sırasıyla) ya da hepsini iptal eder.",
        "which_label": "Hangi zamanlayıcı: söylenen etiket, örn. 'çay'. Söylenmediyse boş bırak.",
        "which_index": "Listedeki sırası (1 en yakını), 'ikincisi' → 2. Söylenmediyse boş bırak.",
        "none": "Kurulu zamanlayıcı yok.",
        "list": "Zamanlayıcılar: {timers}",
        "none_to_cancel": "İptal edilecek zamanlayıcı yoktu.",
        "cancelled": "{count} zamanlayıcı iptal edildi.",
        "cancelled_one": "Saat {time}{label} zamanlayıcısı iptal edildi.",
        "not_found": "Öyle bir zamanlayıcı bulamadım. Kurulu olanlar: {timers}",
        "which": "Birden fazla zamanlayıcı var: {timers}. Hangisini iptal edeyim?",
        "remaining_one": "Saat {time}{label} zamanlayıcısına {duration} kaldı.",
        "remaining_many": "Kalan süreler: {timers}.",
        "hours": "{n} saat", "minutes_left": "{n} dakika", "seconds_left": "{n} saniye",
    },
    AssistantLanguage.ENGLISH: {
        "set": "Sets a timer or an alarm. Use 'minutes'/'seconds' for a duration, 'hour'/'minute' for a time of day.",
        "minutes": "In how many minutes (duration)",
        "seconds": "In how many seconds (duration)",
        "hour": "A time of day, 24-hour clock. '7 am' → 7, '6 pm' → 18",
        "minute": "The minute of that time. 'half past seven' → 30",
        "label": "What it's for in one to three words, e.g. 'tea'. Leave empty if not said.",
        "unclear": "I didn't get the duration or the time.",
        "today": "OK, it's set for {time}.",
        "tomorrow": "OK, it's set for {time} tomorrow.",
        "manage": "Lists the timers and alarms set in Bilge, says the time left, or cancels one (by label or position) or all of them.",
        "which_label": "Which timer: the label said, e.g. 'tea'. Leave empty if not said.",
        "which_index": "Its position in the list (1 is the soonest), 'the second one' → 2. Leave empty if not said.",
        "none": "There are no timers.",
        "list": "Timers: {timers}",
        "none_to_cancel": "There were no timers to cancel.",
        "cancelled": "Cancelled {count} timers.",
        "cancelled_one": "Cancelled the {time}{label} timer.",
        "not_found": "I couldn't find that timer. These are set: {timers}",
        "which": "There are several timers: {timers}. Which one shall I cancel?",
        "remaining_one": "{duration} left on the {time}{label} timer.",
        "remaining_many": "Time left: {timers}.",
        "hours": "{n} h", "minutes_left": "{n} min", "seconds_left": "{n} s",
    },
}  # fmt: skip


def timer_tools(
    service: TimerService, language: AssistantLanguage, clock: Callable[[], datetime] = datetime.now
) -> list[Tool]:
    texts = _TEXTS[language]
    english = language is AssistantLanguage.ENGLISH

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        # The model reliably picks this tool but sometimes garbles numbers ("20:00" → 19), so precise times and
        # durations come from the text itself.
        parsed = (
            english_time_parser.parse(command, appointment=False) if english else timer_phrase_parser.parse(command)
        )
        if parsed is None:
            return arguments
        if parsed.hour is not None:
            minute = parsed.minute or 0
            hour = parsed.hour
            if parsed.either_half_day:
                hour = timer_schedule.nearer_half_day(hour, minute, clock())
            return {**arguments, "hour": hour, "minute": minute, "minutes": None, "seconds": None}
        if parsed.duration_seconds is not None:
            minutes, seconds = divmod(parsed.duration_seconds, 60)
            return {**arguments, "minutes": minutes, "seconds": seconds, "hour": None, "minute": None}
        return arguments

    def set_timer(arguments: dict[str, Any]) -> str:
        now = clock()
        fires_at = timer_schedule.fire_date(
            int_argument(arguments, "minutes"), int_argument(arguments, "seconds"),
            int_argument(arguments, "hour"), int_argument(arguments, "minute"), now,
        )  # fmt: skip
        if fires_at is None:
            raise ToolError(texts["unclear"])
        timer = service.schedule(fires_at, timer_schedule.clean_label(string_argument(arguments, "label")), now)
        same_day = timer.fires_at.date() == now.date()
        return texts["today" if same_day else "tomorrow"].format(time=f"{timer.fires_at:%H:%M}")

    def named(timer: ScheduledTimer) -> dict[str, str]:
        return {"time": f"{timer.fires_at:%H:%M}", "label": f" {timer.label}" if timer.label else ""}

    def listed(timers: list[ScheduledTimer], numbered: bool = False) -> str:
        parts = ["{time}{label}".format(**named(t)) for t in timers]
        return "; ".join(f"{i}) {part}" if numbered else part for i, part in enumerate(parts, 1))

    def duration(timer: ScheduledTimer) -> str:
        left = math.ceil((timer.fires_at - clock()).total_seconds())
        hours, minutes, seconds = timer_choice.split_duration(left)
        parts = [texts["hours"].format(n=hours) if hours else "",
                 texts["minutes_left"].format(n=minutes) if minutes else "",
                 texts["seconds_left"].format(n=seconds) if seconds or not (hours or minutes) else ""]  # fmt: skip
        return " ".join(part for part in parts if part)

    def cancel(timers: list[ScheduledTimer], picked: list[ScheduledTimer], asked: bool) -> str:
        if not picked:
            return texts["not_found"].format(timers=listed(timers))
        if len(picked) > 1:
            # Nothing named one of several: asking beats cancelling the wrong one.
            return texts["which"].format(timers=listed(picked, numbered=not asked))
        service.cancel(picked[0].id)
        return texts["cancelled_one"].format(**named(picked[0]))

    def remaining(timers: list[ScheduledTimer], picked: list[ScheduledTimer]) -> str:
        if not picked:
            return texts["not_found"].format(timers=listed(timers))
        if len(picked) == 1:
            return texts["remaining_one"].format(duration=duration(picked[0]), **named(picked[0]))
        items = "; ".join("{time}{label}: ".format(**named(t)) + duration(t) for t in picked)
        return texts["remaining_many"].format(timers=items)

    def manage(arguments: dict[str, Any]) -> str:
        action = string_argument(arguments, "action")
        if action == TimerAction.CANCEL_ALL:
            count = service.cancel_all()
            return texts["cancelled"].format(count=count) if count else texts["none_to_cancel"]
        timers = service.timers
        if not timers:
            return texts["none_to_cancel" if action == TimerAction.CANCEL else "none"]
        label, index = string_argument(arguments, "label"), int_argument(arguments, "index")
        picked = timer_choice.chosen(timers, label, index)
        if action == TimerAction.CANCEL:
            return cancel(timers, picked, asked=bool(label) or index is not None)
        if action == TimerAction.REMAINING:
            return remaining(timers, picked)
        return texts["list"].format(timers=listed(timers))

    parameters = obj(
        minutes=integer(texts["minutes"], 0, 1440), seconds=integer(texts["seconds"], 0, 3600),
        hour=integer(texts["hour"], 0, 23), minute=integer(texts["minute"], 0, 59), label=text(texts["label"]),
    )  # fmt: skip
    manage_parameters = obj(
        ["action"], action=choice(TimerAction, ""), label=text(texts["which_label"]),
        index=integer(texts["which_index"], 1, 50),
    )  # fmt: skip
    return [
        Tool("setTimer", texts["set"], run=set_timer, parameters=parameters, refine=refine),
        Tool("manageTimers", texts["manage"], run=manage, parameters=manage_parameters),
    ]
