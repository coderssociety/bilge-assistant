"""CalDAV against a real Radicale server on this computer, and the read-only iCal address."""

import threading
from datetime import datetime, timedelta
from wsgiref.simple_server import WSGIRequestHandler, make_server

import httpx
import pytest

from bilge import calendars


class _Quiet(WSGIRequestHandler):
    def log_message(self, *args):
        pass


@pytest.fixture(scope="module")
def caldav_url(tmp_path_factory):
    import caldav
    import radicale
    import radicale.config

    configuration = radicale.config.load()
    configuration.update(
        {"auth": {"type": "none"}, "storage": {"filesystem_folder": str(tmp_path_factory.mktemp("dav"))},
         "rights": {"type": "owner_only"}},
        "test",
    )  # fmt: skip
    server = make_server("127.0.0.1", 0, radicale.Application(configuration), handler_class=_Quiet)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = f"http://127.0.0.1:{server.server_port}/"
    with caldav.DAVClient(url=url, username="ayse", password="x", require_tls=False) as client:
        principal = client.principal()
        principal.make_calendar(name="İş", supported_calendar_component_set=["VEVENT"])
        principal.make_calendar(name="Yapılacaklar", supported_calendar_component_set=["VTODO"])
    yield url
    server.shutdown()


def test_events_round_trip_through_caldav(caldav_url):
    source = calendars.CalDAVSource(caldav_url, "ayse", "x")
    start = datetime.now().astimezone().replace(hour=10, minute=0, second=0, microsecond=0) + timedelta(days=1)
    source.add_event("Diş hekimi", start, start + timedelta(hours=1))

    events = source.events(start - timedelta(hours=2), start + timedelta(hours=4))

    assert [(e.title, e.start, e.all_day) for e in events] == [("Diş hekimi", start, False)]


def test_reminders_go_to_a_task_list_and_can_be_completed(caldav_url):
    source = calendars.CalDAVSource(caldav_url, "ayse", "x")
    due = datetime.now().astimezone().replace(microsecond=0) + timedelta(hours=3)
    source.add_reminder("Süt al", due)
    source.add_reminder("Faturayı öde", None)

    open_titles = {r.title: r.due for r in source.open_reminders()}
    assert open_titles == {"Süt al": due, "Faturayı öde": None}

    assert source.complete_reminder("Süt al")
    assert not source.complete_reminder("Yok böyle bir şey")
    assert [r.title for r in source.open_reminders()] == ["Faturayı öde"]


def test_a_reminder_with_a_due_time_carries_an_alarm(caldav_url):
    import caldav

    source = calendars.CalDAVSource(caldav_url, "ayse", "x")
    due = datetime.now().astimezone().replace(microsecond=0) + timedelta(hours=5)
    source.add_reminder("İlacı al", due)

    with caldav.DAVClient(url=caldav_url, username="ayse", password="x", require_tls=False) as client:
        todos = [t for c in client.principal().calendars() for t in c.search(todo=True)]
        component = next(t.icalendar_component for t in todos if str(t.icalendar_component["SUMMARY"]) == "İlacı al")
    alarm = next(c for c in component.subcomponents if c.name == "VALARM")
    assert (str(alarm["ACTION"]), alarm["TRIGGER"].dt) == ("DISPLAY", due)
    source.complete_reminder("İlacı al")


def _day_events(source, day, title):
    return [e for e in source.events(day, day + timedelta(days=4)) if e.title == title]


def test_an_event_is_moved_keeping_its_length_and_then_deleted(caldav_url):
    source = calendars.CalDAVSource(caldav_url, "ayse", "x")
    start = datetime.now().astimezone().replace(hour=9, minute=0, second=0, microsecond=0) + timedelta(days=10)
    source.add_event("Kuaför", start, start + timedelta(minutes=45))
    [event] = _day_events(source, start - timedelta(hours=9), "Kuaför")
    assert (event.end - event.start, event.recurring) == (timedelta(minutes=45), False)

    later = start + timedelta(days=1, hours=5)
    source.move_event(event, later)

    [moved] = _day_events(source, start - timedelta(hours=9), "Kuaför")
    assert (moved.start, moved.end) == (later, later + timedelta(minutes=45))
    source.delete_event(moved)
    assert _day_events(source, start - timedelta(hours=9), "Kuaför") == []


def _standup(caldav_url, days_ahead, zone=None):
    import caldav

    start = (datetime.now(zone) if zone else datetime.now().astimezone()).replace(
        hour=10, minute=0, second=0, microsecond=0
    ) + timedelta(days=days_ahead)
    with caldav.DAVClient(url=caldav_url, username="ayse", password="x", require_tls=False) as client:
        calendar = next(c for c in client.principal().calendars() if c.get_display_name() == "İş")
        calendar.save_event(dtstart=start, dtend=start + timedelta(minutes=15), summary="Standup",
                            rrule={"FREQ": "DAILY", "COUNT": 3})  # fmt: skip
    return start


@pytest.mark.parametrize("zone", [None, "America/New_York"])
def test_one_occurrence_of_a_repeating_event_is_moved_or_deleted_alone(caldav_url, zone):
    from zoneinfo import ZoneInfo

    source = calendars.CalDAVSource(caldav_url, "ayse", "x")
    start = _standup(caldav_url, 20 if zone is None else 25, ZoneInfo(zone) if zone else None).astimezone()
    first, second, third = _day_events(source, start - timedelta(hours=10), "Standup")
    assert first.recurring and second.start == start + timedelta(days=1)

    source.move_event(second, second.start + timedelta(hours=2))
    source.delete_event(third)

    starts = [e.start for e in _day_events(source, start - timedelta(hours=10), "Standup")]
    assert starts == [start, start + timedelta(days=1, hours=2)]
    # The moved one can be moved again and still knows which occurrence it is.
    moved = _day_events(source, start - timedelta(hours=10), "Standup")[1]
    source.move_event(moved, start + timedelta(days=1, hours=3))
    assert [e.start for e in _day_events(source, start - timedelta(hours=10), "Standup")][1] == (
        start + timedelta(days=1, hours=3)
    )


@pytest.mark.parametrize("zone", [None, "Europe/Istanbul", "America/New_York"])
def test_every_occurrence_is_moved_or_deleted_together(caldav_url, zone):
    from zoneinfo import ZoneInfo

    source = calendars.CalDAVSource(caldav_url, "ayse", "x")
    start = _standup(caldav_url, 30 + 5 * bool(zone) + len(zone or ""), ZoneInfo(zone) if zone else None)
    start = start.astimezone()
    events = _day_events(source, start - timedelta(hours=10), "Standup")
    source.delete_event(events[2])

    source.move_event(events[0], start + timedelta(minutes=30), every=True)

    moved = _day_events(source, start - timedelta(hours=10), "Standup")
    assert [e.start for e in moved] == [start + timedelta(minutes=30), start + timedelta(days=1, minutes=30)]
    assert moved[0].end - moved[0].start == timedelta(minutes=15)
    source.delete_event(moved[1], every=True)
    assert _day_events(source, start - timedelta(hours=10), "Standup") == []


def test_wrong_server_is_a_calendar_error():
    with pytest.raises(calendars.CalendarError):
        calendars.CalDAVSource("http://127.0.0.1:9/", "a", "b").events(datetime.now().astimezone(),
                                                                       datetime.now().astimezone())  # fmt: skip


def test_password_needs_https_except_on_this_computer():
    with pytest.raises(calendars.CalendarError):
        calendars.CalDAVSource("http://dav.example.org/", "a", "b").events(
            datetime.now().astimezone(), datetime.now().astimezone()
        )


ICS = b"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
BEGIN:VEVENT
UID:1
DTSTART:20261016T070000Z
DTEND:20261016T080000Z
SUMMARY:Standup
RRULE:FREQ=DAILY;COUNT=3
END:VEVENT
BEGIN:VEVENT
UID:2
DTSTART;VALUE=DATE:20261017
SUMMARY:Bayram
END:VEVENT
END:VCALENDAR
"""


def test_ics_address_expands_repeating_events_and_is_read_only():
    client = httpx.Client(transport=httpx.MockTransport(lambda request: httpx.Response(200, content=ICS)))
    source = calendars.ICSSource("https://calendar.example.org/secret.ics", client)
    start = datetime(2026, 10, 16).astimezone()

    events = source.events(start, start + timedelta(days=2))

    titles = [(e.title, e.all_day) for e in events]
    assert titles.count(("Standup", False)) == 2
    assert ("Bayram", True) in titles
    with pytest.raises(calendars.ReadOnly):
        source.add_event("x", start, start)
    with pytest.raises(calendars.ReadOnly):
        source.delete_event(events[0])


def test_ics_address_errors_are_calendar_errors():
    client = httpx.Client(transport=httpx.MockTransport(lambda request: httpx.Response(404)))
    with pytest.raises(calendars.CalendarError):
        calendars.ICSSource("https://calendar.example.org/x.ics", client).events(
            datetime.now().astimezone(), datetime.now().astimezone()
        )


def test_plain_http_is_refused_before_any_password_is_sent():
    assert not calendars.is_secure_address("http://nas.lan/dav")
    assert calendars.is_secure_address("http://127.0.0.1:5232/")
    assert calendars.is_secure_address("https://cloud.example.org/dav")
