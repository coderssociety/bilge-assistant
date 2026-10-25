"""Deleting and moving calendar events. The event is found by the words of its title and the day and time said; the
question names the very event that will change, and only that event is changed after the yes."""

from collections.abc import Callable
from datetime import datetime
from typing import TYPE_CHECKING, Any

from bilge import calendars
from bilge.core.language import AssistantLanguage
from bilge.core.text import time_locative
from bilge.core.tools import calendar_change
from bilge.tools.base import Risk, Tool, ToolError
from bilge.tools.desktop.common import int_argument, integer, obj, string_argument, text

if TYPE_CHECKING:
    from bilge.tools.builtin.calendar import Moments

EN, TR = AssistantLanguage.ENGLISH, AssistantLanguage.TURKISH
# Without a day said, the next month is searched for the event.
SEARCH_DAYS = 31
LISTED_MATCHES = 5
MAX_SHIFT_MINUTES = 60 * 24 * 60

_TEXTS = {
    TR: {
        "delete": "Takvimdeki bir etkinliği siler ya da iptal eder ('yarınki toplantıyı iptal et'). Tekrarlanan bir "
        "etkinlikte yalnızca o seferkini, 'hepsini' denirse tümünü.",
        "move": "Takvimdeki bir etkinliğin gününü ya da saatini değiştirir ('diş hekimi randevusunu cumaya al', "
        "'saat 3'teki toplantıyı 4'e ertele', 'toplantıyı bir saat ertele').",
        "title": "Etkinliğin adındaki kelimeler, örn. 'Diş hekimi'; yalnızca gün ya da saat söylendiyse boş",
        "day": "Etkinliğin şu anki günü, bugünden kaç gün sonra; söylenmediyse boş bırak",
        "hour": "Etkinliğin şu anki başlangıç saati; söylenmediyse boş bırak",
        "minute": "Etkinliğin şu anki başlangıç dakikası",
        "new_day": "Yeni gün, bugünden kaç gün sonra",
        "new_hour": "Yeni başlangıç saati, 24 saat biçiminde",
        "new_minute": "Yeni başlangıç dakikası",
        "shift": "Kaç dakika ileri alınacak, öne alınacaksa eksi: 'bir saat ertele' → 60",
        "all": "Tekrarlanan etkinliğin bütün tekrarları için true ('hepsini sil')",
        "at": "{day} saat {time}ki",
        "all_day_at": "{day} tüm gün süren",
        "delete_question": "{when} '{title}' etkinliğini sileyim mi?",
        "delete_one_question": "Tekrarlanan '{title}' etkinliğinin yalnızca {plain} olanını sileyim mi?",
        "delete_all_question": "Tekrarlanan '{title}' etkinliğini tüm tekrarlarıyla sileyim mi?",
        "move_question": "{when} '{title}' etkinliğinin zamanını {new} olarak değiştireyim mi?",
        "move_one_question": "Tekrarlanan '{title}' etkinliğinin yalnızca {plain} olanını {new} olarak "
        "değiştireyim mi?",
        "move_all_question": "Tekrarlanan '{title}' etkinliğinin tüm tekrarlarını saat {time} olarak "
        "değiştireyim mi?",
        "deleted": "Sildim: {plain}, {title}.",
        "deleted_all": "'{title}' etkinliğinin tüm tekrarlarını sildim.",
        "moved": "Taşıdım: {title}, artık {new}.",
        "moved_all": "'{title}' artık her seferinde saat {time}.",
        "not_found": "Takvimde buna uyan bir etkinlik bulamadım.",
        "not_found_title": "Takvimde '{title}' diye bir etkinlik bulamadım.",
        "several": "Birden çok etkinlik buldum: {list}. Hangisini kastediyorsun?",
        "no_new_time": "Etkinliği ne zamana alacağımı anlayamadım.",
        "same_time": "'{title}' zaten {plain}.",
        "series_day": "Tekrarlanan bir etkinliğin tüm tekrarlarını başka bir güne taşıyamam; saatini değiştirebilir "
        "ya da yalnızca bu seferkini taşıyabilirim.",
        "gone": "Hangi etkinliği kastettiğini anlayamadım; yeniden söyler misin?",
    },
    EN: {
        "delete": "Deletes or cancels an event on the calendar ('cancel tomorrow's meeting'). Of a repeating event "
        "only that occurrence, or all of them when the user says so.",
        "move": "Changes the day or time of an event on the calendar ('move the dentist to Friday', 'move the 3 "
        "o'clock meeting to 4', 'push the meeting back an hour').",
        "title": "Words of the event's title, e.g. 'Dentist'; empty when only a day or time was said",
        "day": "The event's current day, days from today; leave empty if not said",
        "hour": "The event's current start hour; leave empty if not said",
        "minute": "The event's current start minute",
        "new_day": "The new day, days from today",
        "new_hour": "The new start hour, 24-hour clock",
        "new_minute": "The new start minute",
        "shift": "Minutes later, negative for earlier: 'push it back an hour' → 60",
        "all": "True for every occurrence of a repeating event ('delete all of them')",
        "at": "{day} at {time}",
        "all_day_at": "{day}, all day",
        "delete_question": "Shall I delete '{title}', {when}?",
        "delete_one_question": "Shall I delete only this occurrence of the repeating event '{title}', {plain}?",
        "delete_all_question": "Shall I delete every occurrence of the repeating event '{title}'?",
        "move_question": "Shall I move '{title}' from {when} to {new}?",
        "move_one_question": "Shall I move only this occurrence of the repeating event '{title}' from {plain} to "
        "{new}?",
        "move_all_question": "Shall I move every occurrence of the repeating event '{title}' to {time}?",
        "deleted": "Deleted: {title}, {plain}.",
        "deleted_all": "Deleted every occurrence of '{title}'.",
        "moved": "Moved: {title} is now {new}.",
        "moved_all": "Every occurrence of '{title}' is now at {time}.",
        "not_found": "I couldn't find a matching event on the calendar.",
        "not_found_title": "I couldn't find '{title}' on the calendar.",
        "several": "I found several events: {list}. Which one do you mean?",
        "no_new_time": "I didn't get when to move the event to.",
        "same_time": "'{title}' is already {plain}.",
        "series_day": "I can't move every occurrence of a repeating event to another day; I can change its time or "
        "move just this one.",
        "gone": "I didn't get which event you mean; could you say it again?",
    },
}  # fmt: skip


def edit_tools(
    connected: Callable[[bool], calendars.CalendarSource],
    guarded: Callable[[Callable[[], Any]], Any],
    moments: "Moments",
    language: AssistantLanguage,
) -> list[Tool]:
    texts = _TEXTS[language]
    english = language is EN
    # What the last question named, so the change made is the one the user said yes to.
    pending: dict[str, tuple[calendars.CalendarEvent, datetime | None]] = {}
    # Why the last question named nothing, said when the change is attempted.
    problem: list[str] = []

    def plain(event: calendars.CalendarEvent) -> str:
        return shown(event.start, event.all_day)

    def shown(start: datetime, all_day: bool) -> str:
        return moments.day_text(start) if all_day else moments.describe(start)

    def located(event: calendars.CalendarEvent) -> str:
        """ "Yarın saat 10:00'daki", "tomorrow at 10:00"."""
        day = moments.day_text(event.start)
        if event.all_day:
            found = texts["all_day_at"].format(day=day)
        else:
            clock = time_locative(event.start.hour, event.start.minute) if language is TR else f"{event.start:%H:%M}"
            found = texts["at"].format(day=day, time=clock)
        return found[:1].upper() + found[1:] if language is TR else found

    def refine(arguments: dict[str, Any], command: str) -> dict[str, Any]:
        """The day, time and new time said in the command win over the model's; an answer such as "ikincisi" keeps
        what the model took from the conversation."""
        change = calendar_change.parse(command, moments.now(), english)
        if not change.commanded:
            return arguments
        event, to = change.event, change.to
        return {"title": arguments.get("title"), "dayOffset": event.day,
                "hour": event.clock[0] if event.clock else None, "minute": event.clock[1] if event.clock else None,
                "eitherHalf": event.either_half, "newDayOffset": to.day,
                "newHour": to.clock[0] if to.clock else None, "newMinute": to.clock[1] if to.clock else None,
                "newEitherHalf": to.either_half, "shiftMinutes": change.shift_minutes, "all": change.every}  # fmt: skip

    def find(arguments: dict[str, Any]) -> calendars.CalendarEvent:
        calendar = connected(True)
        day = int_argument(arguments, "dayOffset")
        hour = int_argument(arguments, "hour")
        clock = (hour, int_argument(arguments, "minute") or 0) if hour is not None else None
        first_day = max(day or 0, 0)
        start = moments.resolve(first_day, 0, 0)
        end = moments.resolve(first_day + (1 if day is not None else SEARCH_DAYS), 0, 0)
        events = guarded(lambda: calendar.events(start, end))
        title = string_argument(arguments, "title")
        when = calendar_change.When(day, clock, bool(arguments.get("eitherHalf")))
        found = calendar_change.matching(events, title, start.date() if day is not None else None, when, english)
        if not found:
            raise ToolError(texts["not_found_title"].format(title=title) if title else texts["not_found"])
        if len(found) > 1:
            listed = "; ".join(f"{plain(e)} {e.title}" for e in found[:LISTED_MATCHES])
            raise ToolError(texts["several"].format(list=listed))
        return found[0]

    def target(arguments: dict[str, Any], event: calendars.CalendarEvent) -> datetime:
        hour = int_argument(arguments, "newHour")
        to = calendar_change.When(
            int_argument(arguments, "newDayOffset"),
            (hour, int_argument(arguments, "newMinute") or 0) if hour is not None else None,
            bool(arguments.get("newEitherHalf")),
        )
        shift = int_argument(arguments, "shiftMinutes")
        shift = max(-MAX_SHIFT_MINUTES, min(shift, MAX_SHIFT_MINUTES)) if shift else None
        change = calendar_change.Change(calendar_change.When(), to, shift, bool(arguments.get("all")), True)
        start = calendar_change.new_start(event.start, event.all_day, change, moments.now().date())
        if start is None:
            raise ToolError(texts["no_new_time"])
        if start == event.start:
            raise ToolError(texts["same_time"].format(title=event.title, plain=plain(event)))
        if change.every and event.recurring and start.date() != event.start.date():
            raise ToolError(texts["series_day"])
        return start

    def key(arguments: dict[str, Any]) -> str:
        return repr(sorted((k, str(v)) for k, v in arguments.items()))

    def prepare(arguments: dict[str, Any], moving: bool) -> tuple[calendars.CalendarEvent, datetime | None] | None:
        pending.clear()
        problem.clear()
        try:
            event = find(arguments)
            prepared = (event, target(arguments, event) if moving else None)
        except ToolError as error:
            problem.append(str(error))
            return None
        pending[key(arguments)] = prepared
        return prepared

    def taken(arguments: dict[str, Any]) -> tuple[calendars.CalendarEvent, datetime | None]:
        prepared = pending.pop(key(arguments), None)
        if prepared is None:
            # Nothing changes that the user didn't hear named in a question.
            raise ToolError(problem[0] if problem else texts["gone"])
        return prepared

    def delete_question(arguments: dict[str, Any]) -> str | None:
        prepared = prepare(arguments, moving=False)
        if prepared is None:
            return None
        event = prepared[0]
        if event.recurring:
            name = "delete_all_question" if arguments.get("all") else "delete_one_question"
            return texts[name].format(title=event.title, plain=plain(event))
        return texts["delete_question"].format(when=located(event), title=event.title)

    def delete(arguments: dict[str, Any]) -> str:
        event, _ = taken(arguments)
        every = bool(arguments.get("all")) and event.recurring
        calendar = connected(True)
        guarded(lambda: calendar.delete_event(event, every))
        if every:
            return texts["deleted_all"].format(title=event.title)
        return texts["deleted"].format(plain=plain(event), title=event.title)

    def move_question(arguments: dict[str, Any]) -> str | None:
        prepared = prepare(arguments, moving=True)
        if prepared is None:
            return None
        event, start = prepared
        if start is None:
            return None
        if event.recurring and arguments.get("all"):
            return texts["move_all_question"].format(title=event.title, time=f"{start:%H:%M}")
        new = shown(start, event.all_day)
        if event.recurring:
            return texts["move_one_question"].format(title=event.title, plain=plain(event), new=new)
        return texts["move_question"].format(when=located(event), title=event.title, new=new)

    def move(arguments: dict[str, Any]) -> str:
        event, start = taken(arguments)
        if start is None:
            raise ToolError(texts["no_new_time"])
        every = bool(arguments.get("all")) and event.recurring
        calendar = connected(True)
        guarded(lambda: calendar.move_event(event, start, every))
        if every:
            return texts["moved_all"].format(title=event.title, time=f"{start:%H:%M}")
        return texts["moved"].format(title=event.title, new=shown(start, event.all_day))

    finding = {
        "title": text(texts["title"]),
        "dayOffset": integer(texts["day"], 0, 366),
        "hour": integer(texts["hour"], 0, 23),
        "minute": integer(texts["minute"], 0, 59),
        "all": {"type": "boolean", "description": texts["all"]},
    }
    return [
        Tool("deleteCalendarEvent", texts["delete"], run=delete, parameters=obj(**finding), risk=Risk.CONFIRM,
             confirmation=delete_question, refine=refine),
        Tool("moveCalendarEvent", texts["move"], run=move, risk=Risk.CONFIRM, confirmation=move_question,
             refine=refine,
             parameters=obj(**finding, newDayOffset=integer(texts["new_day"], 0, 366),
                            newHour=integer(texts["new_hour"], 0, 23), newMinute=integer(texts["new_minute"], 0, 59),
                            shiftMinutes=integer(texts["shift"], -MAX_SHIFT_MINUTES, MAX_SHIFT_MINUTES))),
    ]  # fmt: skip
