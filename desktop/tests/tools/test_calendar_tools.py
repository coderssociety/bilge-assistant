from datetime import datetime, timedelta

import pytest

from bilge import calendars
from bilge.brain.agent import resolve
from bilge.core.language import AssistantLanguage
from bilge.tools.base import Risk, ToolError
from bilge.tools.builtin.calendar import calendar_tools

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
NOW = datetime(2026, 10, 15, 14, 5)


class FakeSource:
    writable = True

    def __init__(self):
        base = NOW.astimezone().replace(hour=0, minute=0)
        self.events_list = [
            calendars.CalendarEvent("Bayram", base + timedelta(days=1), True),
            calendars.CalendarEvent("Diş hekimi", base + timedelta(days=1, hours=10), False),
        ]
        self.added, self.reminders, self.completed = [], [calendars.Reminder("Süt al", None)], []
        self.deleted, self.moved = [], []

    def events(self, start, end):
        return [e for e in self.events_list if start <= e.start < end]

    def add_event(self, title, start, end):
        self.added.append((title, start, end))

    def delete_event(self, event, every=False):
        self.deleted.append((event.title, event.start, every))

    def move_event(self, event, start, every=False):
        self.moved.append((event.title, event.start, start, every))

    def open_reminders(self):
        return self.reminders

    def add_reminder(self, title, due):
        self.added.append((title, due))

    def complete_reminder(self, title):
        self.completed.append(title)
        return True


def tools(source, language=TR, alert=None):
    return {tool.name: tool for tool in calendar_tools(lambda: source, language, clock=lambda: NOW, alert=alert)}


def when(tool, said, language=TR, model=None):
    refined = tool.refine(dict(model or {"title": "x"}), resolve(said, language))
    return refined["dayOffset"], refined["hour"], refined["minute"]


def test_reading_tomorrow_and_the_week():
    found = tools(FakeSource())
    assert found["readCalendar"].run({"range": "tomorrow"}) == "Yarın 2 etkinlik var: tüm gün: Bayram; 10:00 Diş hekimi"
    assert found["readCalendar"].run({"range": "today"}) == "Bugün takvimde etkinlik yok."
    week = found["readCalendar"].run({"range": "thisWeek"})
    assert week == "Önümüzdeki 7 günde 2 etkinlik var: Cuma tüm gün: Bayram; Cuma 10:00 Diş hekimi"
    assert found["readCalendar"].untrusted_output


def test_the_time_comes_from_the_words_not_the_model():
    add = tools(FakeSource())["addCalendarEvent"]
    refined = add.refine({"title": "Diş hekimi", "dayOffset": 0, "hour": 9}, "yarın 10:00'da diş hekimi ekle")
    assert (refined["dayOffset"], refined["hour"], refined["minute"]) == (1, 10, 0)
    # An hour the user never said is dropped.
    assert add.refine({"title": "x", "hour": 15}, "yarın toplantı ekle")["hour"] is None
    # A part of the day keeps the model's hour.
    assert add.refine({"title": "x", "hour": 19}, "yarın akşam yemek ekle")["hour"] == 19


def test_adding_an_event_asks_with_the_day_and_time():
    source = FakeSource()
    add = tools(source)["addCalendarEvent"]
    arguments = {"title": "Diş hekimi", "dayOffset": 1, "hour": 10, "minute": 0}
    assert add.question(arguments) == "Yarın saat 10:00 için 'Diş hekimi' etkinliğini takvime ekleyeyim mi?"
    assert add.run(arguments) == "Ekledim: yarın saat 10:00, Diş hekimi."
    title, start, end = source.added[0]
    assert (title, start.hour, end - start) == ("Diş hekimi", 10, timedelta(hours=1))
    later = {"title": "Konser", "dayOffset": 3, "hour": 20}
    assert tools(source, EN)["addCalendarEvent"].question(later) == (
        "Shall I add 'Konser' to your calendar for Sunday 18 October at 20:00?"
    )


def test_reminders_are_listed_added_and_completed_by_a_loose_name():
    source = FakeSource()
    found = tools(source)
    assert found["readReminders"].run({}) == "1 anımsatıcı var: Süt al"
    assert found["addReminder"].question({"title": "Ekmek al"}) == "'Ekmek al' anımsatıcısını ekleyeyim mi?"
    complete = found["completeReminder"]
    arguments = complete.refine({"title": "süt"}, "süt almayı tamamladım işaretle")
    assert complete.run(arguments) == "'Süt al' tamamlandı olarak işaretlendi."
    assert source.completed == ["Süt al"]


def test_unconfigured_read_only_and_unreachable_calendars_are_explained():
    with pytest.raises(ToolError, match="Takvim sekmesinden"):
        {t.name: t for t in calendar_tools(lambda: None, TR)}["readCalendar"].run({"range": "today"})
    read_only = FakeSource()
    read_only.writable = False
    with pytest.raises(ToolError, match="yalnızca okunabiliyor"):
        tools(read_only)["addReminder"].run({"title": "x"})

    class Down(FakeSource):
        def events(self, start, end):
            raise calendars.CalendarError("down")

    with pytest.raises(ToolError, match="Takvime ulaşamadım"):
        tools(Down())["readCalendar"].run({"range": "today"})


def test_a_date_the_parser_does_not_know_keeps_the_models_day():
    add = tools(FakeSource())["addCalendarEvent"]
    refined = add.refine({"title": "Toplantı", "dayOffset": 31, "hour": 10}, "15 Kasım'da 10:00'da toplantı ekle")
    assert (refined["dayOffset"], refined["hour"]) == (31, 10)


@pytest.mark.skipif(not hasattr(__import__("time"), "tzset"), reason="needs time.tzset to change the zone")
def test_wall_clock_times_survive_a_change_to_summer_time(monkeypatch):
    import time

    monkeypatch.setenv("TZ", "Europe/Berlin")
    time.tzset()
    try:
        from bilge.tools.builtin.calendar import Moments

        moments = Moments(EN, clock=lambda: datetime(2026, 3, 25, 12, 0))
        moment = moments.resolve(10, 9, 0)
        assert (moment.hour, moment.utcoffset()) == (9, timedelta(hours=2))
        assert calendars.local(datetime(2026, 7, 1, 8, 0, tzinfo=__import__("datetime").timezone.utc))[0].hour == 10
    finally:
        monkeypatch.delenv("TZ")
        time.tzset()


def test_a_given_day_or_next_week_is_read_from_the_words():
    source = FakeSource()
    source.events_list.append(calendars.CalendarEvent("Kurs", NOW.astimezone().replace(hour=18, minute=0)
                                                      + timedelta(days=4), False))  # fmt: skip
    read = tools(source)["readCalendar"]
    friday = read.refine({"range": "today"}, "cuma ne var")
    assert friday == {"range": "day", "dayOffset": 1}
    assert read.run(friday) == "Yarın 2 etkinlik var: tüm gün: Bayram; 10:00 Diş hekimi"
    monday = read.refine({"range": "thisWeek"}, "haftaya pazartesi ne var")
    assert read.run(monday) == "26 Ekim Pazartesi takvimde etkinlik yok."
    assert read.run(read.refine({"range": "today"}, "önümüzdeki hafta ne var")) == (
        "Önümüzdeki hafta 1 etkinlik var: Pazartesi 18:00 Kurs"
    )
    assert read.refine({"range": "thisWeek"}, "takvimde ne var") == {"range": "thisWeek"}
    english = tools(source, EN)["readCalendar"]
    assert english.run(english.refine({}, "what's on Monday")) == "On Monday 19 October there are 1 events: 18:00 Kurs"


def test_small_hours_said_bare_are_in_the_afternoon():
    add = tools(FakeSource())["addCalendarEvent"]
    assert when(add, "yarın saat ikide toplantı ekle") == (1, 14, 0)
    assert when(add, "yarın sabah saat ikide uçuş ekle") == (1, 2, 0)
    assert when(add, "cuma akşam sekizde yemek ekle") == (1, 20, 0)
    assert when(add, "yarın dokuz buçukta toplantı") == (1, 9, 30)


def test_dates_relative_days_and_the_models_day():
    add = tools(FakeSource())["addCalendarEvent"]
    assert when(add, "15 Kasım'da saat üçte toplantı ekle") == (31, 15, 0)
    assert when(add, "yarından sonra saat onda") == (2, 10, 0)
    assert when(add, "öbür gün saat onda") == (2, 10, 0)
    assert when(add, "haftaya saat onda") == (7, 10, 0)
    assert when(add, "iki hafta sonra saat onda") == (14, 10, 0)
    # The parser finds no day: the model's stays.
    assert when(add, "o gün saat onda", model={"title": "x", "dayOffset": 5}) == (5, 10, 0)
    assert when(tools(FakeSource(), EN)["addCalendarEvent"], "on November 15 at 3", EN) == (31, 15, 0)


def test_a_time_already_past_today_means_tomorrow():
    add = tools(FakeSource())["addCalendarEvent"]
    # It is 14:05.
    assert when(add, "saat ikide toplantı ekle", model={"title": "x", "dayOffset": 0}) == (1, 14, 0)
    assert when(add, "saat üçte toplantı ekle") == (None, 15, 0)
    assert when(add, "bugün saat ikide toplantı ekle") == (0, 14, 0)


def test_reminders_in_a_while_are_from_now():
    remind = tools(FakeSource())["addReminder"]
    assert when(remind, "yarım saat sonra çayı hatırlat") == (0, 14, 35)
    assert when(remind, "iki saat sonra hatırlat") == (0, 16, 5)
    assert when(remind, "on saat sonra hatırlat") == (1, 0, 5)
    assert when(tools(FakeSource(), EN)["addReminder"], "remind me in half an hour", EN) == (0, 14, 35)


def test_listed_reminders_say_when_they_are_due():
    source = FakeSource()
    source.reminders.append(calendars.Reminder("Ekmek al", NOW.astimezone().replace(hour=9, minute=0)
                                               + timedelta(days=1)))  # fmt: skip
    assert tools(source)["readReminders"].run({}) == "2 anımsatıcı var: Süt al; Ekmek al (yarın saat 09:00)"
    assert tools(source, EN)["readReminders"].run({}) == "2 reminders: Süt al; Ekmek al (tomorrow at 09:00)"


def test_a_reminder_due_later_is_also_said_out_loud():
    alerts = []
    remind = tools(FakeSource(), alert=lambda due, title: alerts.append((due.hour, due.minute, title)))["addReminder"]
    assert remind.run({"title": "Çay", "dayOffset": 0, "hour": 14, "minute": 35}) == (
        "Ekledim, bugün saat 14:35 hatırlatacağım."
    )
    remind.run({"title": "Geçmiş", "dayOffset": 0, "hour": 9, "minute": 0})
    remind.run({"title": "Tarihsiz"})
    assert alerts == [(14, 35, "Çay")]


def test_a_broken_alert_does_not_lose_the_reminder():
    source = FakeSource()

    def broken(due, title):
        raise RuntimeError("no timers")

    reply = tools(source, alert=broken)["addReminder"].run({"title": "Çay", "dayOffset": 1, "hour": 9})
    assert reply.startswith("Ekledim") and source.added[0][0] == "Çay"


def _at(days, hour, minute=0):
    return NOW.astimezone().replace(hour=hour, minute=minute) + timedelta(days=days)


def asked_and_run(tool, said, language=TR, model=None):
    arguments = tool.refine(dict(model or {}), resolve(said, language))
    return tool.question(arguments), arguments


def test_an_event_is_deleted_after_a_question_naming_it():
    source = FakeSource()
    delete = tools(source)["deleteCalendarEvent"]
    question, arguments = asked_and_run(
        delete, "yarınki diş hekimi randevusunu iptal et", model={"title": "Diş hekimi"}
    )
    assert question == "Yarın saat 10:00'daki 'Diş hekimi' etkinliğini sileyim mi?"
    assert delete.run(arguments) == "Sildim: yarın saat 10:00, Diş hekimi."
    assert source.deleted == [("Diş hekimi", _at(1, 10), False)]
    assert delete.risk is Risk.CONFIRM


def test_an_event_is_moved_to_the_day_or_time_said():
    source = FakeSource()
    source.events_list.append(calendars.CalendarEvent("Ekip toplantısı", _at(0, 15), False, _at(0, 16)))
    move = tools(source)["moveCalendarEvent"]
    question, arguments = asked_and_run(move, "diş hekimi randevusunu pazartesiye al", model={"title": "diş hekimi"})
    assert (
        question
        == "Yarın saat 10:00'daki 'Diş hekimi' etkinliğinin zamanını 19 Ekim Pazartesi saat 10:00 olarak değiştireyim mi?"
    )
    assert move.run(arguments) == "Taşıdım: Diş hekimi, artık 19 Ekim Pazartesi saat 10:00."
    # Only a time said for the event: the generic "toplantı" finds the one meeting at three.
    question, arguments = asked_and_run(move, "saat üçteki toplantıyı dörde ertele", model={"title": "toplantı"})
    assert (
        question
        == "Bugün saat 15:00'teki 'Ekip toplantısı' etkinliğinin zamanını bugün saat 16:00 olarak değiştireyim mi?"
    )
    move.run(arguments)
    _, arguments = asked_and_run(move, "ekip toplantısını bir saat öne al", model={"title": "ekip toplantısı"})
    move.run(arguments)
    assert [(title, new.hour) for title, _, new, _ in source.moved] == [
        ("Diş hekimi", 10),
        ("Ekip toplantısı", 16),
        ("Ekip toplantısı", 14),
    ]


def test_several_matching_events_are_listed_and_nothing_changes():
    source = FakeSource()
    source.events_list.append(calendars.CalendarEvent("Diş hekimi kontrol", _at(1, 16), False))
    source.events_list.append(calendars.CalendarEvent("Diş hekimi", _at(1, 17), False))
    delete = tools(source)["deleteCalendarEvent"]
    question, arguments = asked_and_run(delete, "yarınki diş hekimini sil", model={"title": "diş hekimi"})
    assert question is None
    with pytest.raises(
        ToolError, match="Birden çok etkinlik buldum: yarın saat 10:00 Diş hekimi; yarın saat 17:00 Diş hekimi"
    ):
        delete.run(arguments)
    # The answer "the five o'clock one" leaves the choice to the model.
    answer = delete.refine({"title": "Diş hekimi", "dayOffset": 1, "hour": 17}, "saat beştekini")
    assert delete.question(answer) == "Yarın saat 17:00'deki 'Diş hekimi' etkinliğini sileyim mi?"
    delete.run(answer)
    assert source.deleted == [("Diş hekimi", _at(1, 17), False)]


def test_nothing_found_and_no_new_time_are_explained():
    found = tools(FakeSource())
    _, arguments = asked_and_run(found["deleteCalendarEvent"], "berber randevusunu sil", model={"title": "berber"})
    with pytest.raises(ToolError, match="'berber' diye bir etkinlik bulamadım"):
        found["deleteCalendarEvent"].run(arguments)
    _, arguments = asked_and_run(found["moveCalendarEvent"], "diş hekimini ertele", model={"title": "diş hekimi"})
    with pytest.raises(ToolError, match="ne zamana alacağımı"):
        found["moveCalendarEvent"].run(arguments)


def test_a_repeating_event_changes_one_occurrence_unless_all_are_asked_for():
    source = FakeSource()
    source.events_list = [calendars.CalendarEvent("Standup", _at(day, 9, 30), False, _at(day, 9, 45), True)
                          for day in range(1, 4)]  # fmt: skip
    found = tools(source)
    question, arguments = asked_and_run(
        found["deleteCalendarEvent"], "yarınki standup'ı sil", model={"title": "Standup"}
    )
    assert question == "Tekrarlanan 'Standup' etkinliğinin yalnızca yarın saat 09:30 olanını sileyim mi?"
    found["deleteCalendarEvent"].run(arguments)
    question, arguments = asked_and_run(found["moveCalendarEvent"], "standup'ların hepsini 10:00'a al",
                                        model={"title": "Standup"})  # fmt: skip
    assert question == "Tekrarlanan 'Standup' etkinliğinin tüm tekrarlarını saat 10:00 olarak değiştireyim mi?"
    found["moveCalendarEvent"].run(arguments)
    assert source.deleted == [("Standup", _at(1, 9, 30), False)]
    assert source.moved == [("Standup", _at(1, 9, 30), _at(1, 10), True)]
    _, arguments = asked_and_run(found["moveCalendarEvent"], "standup'ların hepsini pazartesiye al",
                                 model={"title": "Standup"})  # fmt: skip
    with pytest.raises(ToolError, match="başka bir güne taşıyamam"):
        found["moveCalendarEvent"].run(arguments)


def test_a_read_only_calendar_cannot_be_changed():
    source = FakeSource()
    source.writable = False
    delete = tools(source)["deleteCalendarEvent"]
    _, arguments = asked_and_run(delete, "yarınki diş hekimini sil", model={"title": "diş hekimi"})
    with pytest.raises(ToolError, match="yalnızca okunabiliyor"):
        delete.run(arguments)
    assert source.deleted == []


def test_english_changes_name_the_event_and_the_new_time():
    source = FakeSource()
    found = tools(source, EN)
    question, arguments = asked_and_run(found["moveCalendarEvent"], "move the dentist appointment to Monday at 4", EN,
                                        model={"title": "dentist appointment"})  # fmt: skip
    assert question is None
    source.events_list[1] = calendars.CalendarEvent("Dentist", _at(1, 10), False)
    question, arguments = asked_and_run(found["moveCalendarEvent"], "move the dentist appointment to Monday at 4", EN,
                                        model={"title": "dentist appointment"})  # fmt: skip
    assert question == "Shall I move 'Dentist' from tomorrow at 10:00 to Monday 19 October at 16:00?"
    assert found["moveCalendarEvent"].run(arguments) == "Moved: Dentist is now Monday 19 October at 16:00."
    question, arguments = asked_and_run(found["deleteCalendarEvent"], "cancel tomorrow's dentist", EN,
                                        model={"title": "dentist"})  # fmt: skip
    assert question == "Shall I delete 'Dentist', tomorrow at 10:00?"
