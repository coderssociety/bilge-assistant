"""The user's calendar and reminders: a CalDAV account (Nextcloud, iCloud, Fastmail, Radicale and others) or a
read-only iCal address (Google Calendar's "secret address in iCal format")."""

import ipaddress
import logging
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, time, timedelta
from typing import Protocol
from urllib.parse import urlsplit

import httpx

log = logging.getLogger(__name__)

TIMEOUT_SECONDS = 15
MAX_ICS_BYTES = 10_000_000


class CalendarError(Exception):
    pass


class NotConfigured(CalendarError):
    pass


class ReadOnly(CalendarError):
    pass


@dataclass(frozen=True)
class CalendarEvent:
    title: str
    # Local time, timezone-aware; midnight for all-day events.
    start: datetime
    all_day: bool
    end: datetime | None = None
    # One occurrence of a repeating event.
    recurring: bool = False
    # Where the source finds the event again to change it; its own business.
    reference: tuple[str, ...] = field(default=(), compare=False)


@dataclass(frozen=True)
class Reminder:
    title: str
    due: datetime | None


class CalendarSource(Protocol):
    writable: bool

    def events(self, start: datetime, end: datetime) -> list[CalendarEvent]: ...

    def add_event(self, title: str, start: datetime, end: datetime) -> None: ...

    def delete_event(self, event: CalendarEvent, every: bool = False) -> None:
        """Deletes the event; of a repeating one only this occurrence unless `every`."""
        ...

    def move_event(self, event: CalendarEvent, start: datetime, every: bool = False) -> None:
        """Moves the event to begin at `start`, keeping its length; of a repeating one only this occurrence unless
        `every`, which moves the whole series by as much."""
        ...

    def open_reminders(self) -> list[Reminder]: ...

    def add_reminder(self, title: str, due: datetime | None) -> None: ...

    def complete_reminder(self, title: str) -> bool:
        """Marks the open reminder with exactly this title done; False when there is none."""
        ...


def local(moment: date | datetime) -> tuple[datetime, bool]:
    """(local aware time, all day) for an iCalendar DTSTART, which may be a date, a naive or an aware datetime."""
    if not isinstance(moment, datetime):
        return datetime.combine(moment, time()).astimezone(), True
    # astimezone() without a zone picks the local offset for that instant, so summer events keep summer time.
    return moment.astimezone(), False


def _summary(component) -> str:
    return str(component.get("SUMMARY") or "").strip()


def _event(component, url: str = "") -> CalendarEvent | None:
    """None for an event without a start, which some servers keep."""
    start = component.get("DTSTART")
    if start is None:
        return None
    begins, all_day = local(start.dt)
    ends = component.get("DTEND")
    if ends is not None:
        finishes = local(ends.dt)[0]
    elif component.get("DURATION") is not None:
        finishes = begins + component["DURATION"].dt
    else:
        finishes = begins + (timedelta(days=1) if all_day else timedelta())
    occurrence = component.get("RECURRENCE-ID")
    recurring = occurrence is not None or "RRULE" in component
    reference = (url, local(occurrence.dt)[0].isoformat() if occurrence is not None else "")
    return CalendarEvent(_summary(component), begins, all_day, finishes, recurring, reference)


def _sorted(events: list[CalendarEvent]) -> list[CalendarEvent]:
    return sorted(events, key=lambda e: (e.start, not e.all_day, e.title))


class CalDAVSource:
    writable = True

    def __init__(self, url: str, username: str, password: str, calendar_name: str = ""):
        self.url = url
        self.username = username
        self.password = password
        self.calendar_name = calendar_name

    def _client(self):
        import caldav

        # A password never goes over plain HTTP, except to a server on this computer. caldav's require_tls only
        # covers its own discovery, so an http:// address is refused here.
        if not is_secure_address(self.url):
            raise CalendarError("A CalDAV address must start with https://")
        return caldav.DAVClient(url=self.url, username=self.username or None, password=self.password or None,
                                timeout=TIMEOUT_SECONDS, require_tls=not _is_loopback_http(self.url))  # fmt: skip

    def _calendars(self, client) -> list:
        from caldav.lib.error import DAVError

        try:
            calendars = client.principal().calendars()
        except DAVError:
            # The address may point at one calendar rather than the account.
            calendars = [client.calendar(url=self.url)]
        if not calendars:
            raise CalendarError("The account has no calendars")
        return calendars

    def _run(self, action):
        from caldav.lib.error import AuthorizationError, DAVError

        try:
            with self._client() as client:
                return action(client)
        except AuthorizationError as error:
            raise CalendarError("The calendar server refused the user name or password") from error
        except (DAVError, OSError, ValueError) as error:
            raise CalendarError(f"Calendar server: {type(error).__name__}: {error}") from error

    def events(self, start: datetime, end: datetime) -> list[CalendarEvent]:
        def read(client) -> list[CalendarEvent]:
            from caldav.lib.error import DAVError

            found = []
            for calendar in self._calendars(client):
                try:
                    results = calendar.search(start=start, end=end, event=True, expand=True)
                except DAVError:
                    # A task-only list can refuse event searches; the others still count.
                    log.info("Skipping a calendar that refused the search", exc_info=True)
                    continue
                for result in results:
                    event = _event(result.icalendar_component, str(result.url))
                    if event is not None:
                        found.append(event)
            return _sorted(found)

        return self._run(read)

    def _target(self, client, component: str):
        calendars = self._calendars(client)
        if self.calendar_name:
            for calendar in calendars:
                if (calendar.get_display_name() or "").strip().lower() == self.calendar_name.strip().lower():
                    return calendar
        for calendar in calendars:
            try:
                if component in calendar.get_supported_components():
                    return calendar
            except Exception:  # noqa: BLE001 - servers that don't answer this simply take everything
                return calendar
        return calendars[0]

    def add_event(self, title: str, start: datetime, end: datetime) -> None:
        self._run(lambda client: self._target(client, "VEVENT").save_event(dtstart=start, dtend=end, summary=title))

    def _resource(self, client, event: CalendarEvent):
        url = event.reference[0] if event.reference else ""
        for calendar in self._calendars(client) if url else []:
            if url.startswith(str(calendar.url)):
                resource = calendar.event_by_url(url)
                resource.load()
                return resource
        raise CalendarError("The event is no longer on the server")

    def delete_event(self, event: CalendarEvent, every: bool = False) -> None:
        def delete(client) -> None:
            resource = self._resource(client, event)
            calendar = resource.icalendar_instance
            master = _master(calendar)
            if every or not _repeats(master):
                resource.delete()
                return
            moment = _occurrence(event)
            for override in _overrides(calendar, moment):
                calendar.subcomponents.remove(override)
            master.add("EXDATE", _like(master["DTSTART"].dt, moment))
            resource.save(only_this_recurrence=False)

        self._run(delete)

    def move_event(self, event: CalendarEvent, start: datetime, every: bool = False) -> None:
        def move(client) -> None:
            resource = self._resource(client, event)
            calendar = resource.icalendar_instance
            master = _master(calendar)
            if not _repeats(master):
                _set_times(master, start, event)
            elif every:
                _shift_series(calendar, master, start.replace(tzinfo=None) - event.start.replace(tzinfo=None))
            else:
                moment = _occurrence(event)
                override = next(iter(_overrides(calendar, moment)), None) or _new_override(calendar, master, moment)
                _set_times(override, start, event)
            resource.save(only_this_recurrence=False)

        self._run(move)

    def _open_todos(self, client) -> list:
        from caldav.lib.error import DAVError

        todos = []
        for calendar in self._calendars(client):
            try:
                todos.extend(calendar.search(todo=True, include_completed=False))
            except DAVError:
                continue
        return todos

    def open_reminders(self) -> list[Reminder]:
        def read(client) -> list[Reminder]:
            reminders = []
            for todo in self._open_todos(client):
                component = todo.icalendar_component
                due = component.get("DUE")
                reminders.append(Reminder(_summary(component), local(due.dt)[0] if due else None))
            return reminders

        return self._run(read)

    def add_reminder(self, title: str, due: datetime | None) -> None:
        details: dict = {"summary": title}
        if due is not None:
            # A to-do's DUE alone alerts nobody; the alarm makes the user's phone or desktop client say it.
            details |= {"due": due, "alarm_trigger": due.astimezone(UTC), "alarm_action": "DISPLAY",
                        "alarm_description": title}  # fmt: skip
        self._run(lambda client: self._target(client, "VTODO").save_todo(**details))

    def complete_reminder(self, title: str) -> bool:
        def complete(client) -> bool:
            for todo in self._open_todos(client):
                if _summary(todo.icalendar_component) == title:
                    todo.complete()
                    return True
            return False

        return self._run(complete)


class ICSSource:
    """A published calendar address; it can be read but not changed."""

    writable = False

    def __init__(self, url: str, client: httpx.Client | None = None):
        self.url = url
        self._client = client

    def _calendar(self):
        import icalendar

        client = self._client or httpx.Client(timeout=TIMEOUT_SECONDS, follow_redirects=True)
        try:
            with client.stream("GET", self.url) as response:
                # A redirect must not carry the secret address over to plain HTTP.
                if response.url.scheme != "https" and not _is_loopback_http(str(response.url)):
                    raise CalendarError("The calendar address left HTTPS")
                if response.status_code != 200:
                    raise CalendarError(f"Calendar address answered {response.status_code}")
                body = bytearray()
                for chunk in response.iter_bytes():
                    body.extend(chunk)
                    if len(body) > MAX_ICS_BYTES:
                        raise CalendarError("Calendar too large")
        except httpx.HTTPError as error:
            raise CalendarError(f"Calendar address: {type(error).__name__}") from error
        finally:
            if self._client is None:
                client.close()
        try:
            return icalendar.Calendar.from_ical(bytes(body))
        except (ValueError, IndexError, KeyError) as error:
            raise CalendarError("Not an iCalendar file") from error

    def events(self, start: datetime, end: datetime) -> list[CalendarEvent]:
        import recurring_ical_events

        found = []
        for component in recurring_ical_events.of(self._calendar()).between(start, end):
            event = _event(component) if component.name == "VEVENT" else None
            if event is not None:
                found.append(event)
        return _sorted(found)

    def add_event(self, title: str, start: datetime, end: datetime) -> None:
        raise ReadOnly("An iCal address is read-only")

    def delete_event(self, event: CalendarEvent, every: bool = False) -> None:
        raise ReadOnly("An iCal address is read-only")

    def move_event(self, event: CalendarEvent, start: datetime, every: bool = False) -> None:
        raise ReadOnly("An iCal address is read-only")

    def open_reminders(self) -> list[Reminder]:
        return []

    def add_reminder(self, title: str, due: datetime | None) -> None:
        raise ReadOnly("An iCal address is read-only")

    def complete_reminder(self, title: str) -> bool:
        raise ReadOnly("An iCal address is read-only")


_SERIES_ONLY = ("RRULE", "RDATE", "EXDATE", "RECURRENCE-ID", "DTSTART", "DTEND", "DURATION", "SEQUENCE")


def _master(calendar):
    events = [c for c in calendar.subcomponents if c.name == "VEVENT"]
    if not events:
        raise CalendarError("The calendar entry holds no event")
    return next((e for e in events if "RECURRENCE-ID" not in e), events[0])


def _repeats(master) -> bool:
    return "RRULE" in master or "RDATE" in master


def _occurrence(event: CalendarEvent) -> datetime:
    """The start the repetition rule gives this occurrence, which a moved one no longer begins at."""
    said = event.reference[1] if len(event.reference) > 1 else ""
    return datetime.fromisoformat(said) if said else event.start


def _overrides(calendar, moment: datetime) -> list:
    return [c for c in calendar.subcomponents if c.name == "VEVENT" and "RECURRENCE-ID" in c
            and local(c["RECURRENCE-ID"].dt)[0] == moment]  # fmt: skip


def _like(template: date | datetime, moment: datetime) -> date | datetime:
    """`moment` written as `template` is: a date, a floating local time, or a time in the template's own zone."""
    if not isinstance(template, datetime):
        return moment.date()
    if template.tzinfo is None:
        return moment.astimezone().replace(tzinfo=None)
    return moment.astimezone(template.tzinfo)


def _replace(component, name: str, value) -> None:
    component.pop(name, None)
    component.add(name, value)


def _set_times(component, start: datetime, event: CalendarEvent) -> None:
    length = (event.end - event.start) if event.end is not None else timedelta(hours=1)
    template = component["DTSTART"].dt
    _replace(component, "DTSTART", _like(template, start))
    if "DTEND" in component:
        _replace(component, "DTEND", _like(component["DTEND"].dt, start + length))


def _new_override(calendar, master, moment: datetime):
    import icalendar

    override = icalendar.Event()
    for name, value in master.items():
        if name not in _SERIES_ONLY:
            override[name] = value
    template = master["DTSTART"].dt
    override.add("RECURRENCE-ID", _like(template, moment))
    override.add("DTSTART", _like(template, moment))
    if "DTEND" in master:
        override.add("DTEND", _like(master["DTEND"].dt, moment))
    calendar.add_component(override)
    return override


def _shift_series(calendar, master, delta: timedelta) -> None:
    """Every occurrence, and the dates that point at them (skipped ones, changed ones), by the same wall-clock time."""
    for name in ("DTSTART", "DTEND"):
        if name in master:
            _replace(master, name, master[name].dt + delta)
    skipped = master.pop("EXDATE", None)
    for entry in skipped if isinstance(skipped, list) else [skipped] if skipped is not None else []:
        for moment in entry.dts:
            master.add("EXDATE", moment.dt + delta)
    for component in calendar.subcomponents:
        if component.name == "VEVENT" and "RECURRENCE-ID" in component:
            _replace(component, "RECURRENCE-ID", component["RECURRENCE-ID"].dt + delta)


def is_secure_address(url: str) -> bool:
    return urlsplit(url).scheme.lower() == "https" or _is_loopback_http(url)


def _is_loopback_http(url: str) -> bool:
    parts = urlsplit(url)
    if parts.scheme != "http" or not parts.hostname:
        return False
    if parts.hostname == "localhost":
        return True
    try:
        return ipaddress.ip_address(parts.hostname).is_loopback
    except ValueError:
        return False
