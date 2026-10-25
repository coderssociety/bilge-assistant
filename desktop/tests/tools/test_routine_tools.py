import json
from datetime import datetime, timedelta

import pytest

from bilge.brain.agent import Agent
from bilge.core.language import AssistantLanguage
from bilge.core.routines.routine_schedule import EVERY_DAY, WEEKDAYS, Routine
from bilge.tools.base import Registry
from bilge.tools.builtin import routines

from ..brain.test_agent import ScriptedProvider

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
# A Thursday evening.
NOW = datetime(2026, 10, 15, 20, 59, 50)


def tools_for(store, language=TR):
    return {tool.name: tool for tool in routines.routine_tools(store, language)}


def agent_for(store, answers=(), language=TR):
    asked, pending = [], list(answers)

    def confirm(question):
        asked.append(question)
        return pending.pop(0)

    agent = Agent(ScriptedProvider(), Registry(routines.routine_tools(store, language)), confirm, language,
                  clock=lambda: NOW, rules=routines.routine_rules(language))  # fmt: skip
    return agent, asked


def test_a_spoken_routine_is_read_back_and_kept_only_after_a_yes(tmp_path):
    store = routines.RoutineStore(tmp_path / "routines.json")
    agent, asked = agent_for(store, answers=[False, True])
    assert agent.handle("her gece 21'de hava durumunu söyle").text == "Tamam, yapmıyorum."
    assert asked == ["Her gün 21:00'de “hava durumunu söyle” rutinini kurayım mı?"]
    assert store.load() == []
    reply = agent.handle("hafta içi her gün yedide haberleri oku").text
    assert reply == "Tamam, rutin kuruldu: hafta içi her gün 07:00'de “haberleri oku”."
    assert [(r.days, r.hour, r.minute, r.command) for r in store.load()] == [(WEEKDAYS, 7, 0, "haberleri oku")]


def test_the_summary_command_inside_a_routine_is_not_run_now(tmp_path):
    store = routines.RoutineStore(tmp_path / "routines.json")
    agent, asked = agent_for(store, answers=[True])
    assert agent.handle("her sabah sekizde günün özetini oku").text.startswith("Tamam, rutin kuruldu")
    assert store.load()[0].command == "günün özetini oku"


def test_routines_are_listed_and_deleted_by_voice(tmp_path):
    store = routines.RoutineStore(tmp_path / "routines.json")
    store.add(Routine("a", EVERY_DAY, 21, 0, "hava durumunu söyle"))
    store.add(Routine("b", EVERY_DAY, 19, 0, "salonun ışığını aç"))
    agent, asked = agent_for(store, answers=[True, True])
    assert agent.handle("rutinlerim neler").text == (
        "2 rutin var: her gün 19:00'da “salonun ışığını aç”; her gün 21:00'de “hava durumunu söyle”."
    )
    assert agent.handle("akşam rutinini sil").text == "Rutin silindi: her gün 19:00'da “salonun ışığını aç”."
    assert [r.id for r in store.load()] == ["a"]
    assert agent.handle("bütün rutinleri sil").text == "1 rutin silindi."
    assert agent.handle("rutinlerim neler").text == "Kurulu rutin yok."
    assert asked == [
        "Her gün 19:00'da “salonun ışığını aç” rutinini sileyim mi?",
        "1 rutinin hepsini sileyim mi: her gün 21:00'de “hava durumunu söyle”?",
    ]


def test_a_routine_is_deleted_only_after_a_yes(tmp_path):
    store = routines.RoutineStore(tmp_path / "routines.json")
    store.add(Routine("a", EVERY_DAY, 8, 0, "günün özetini oku"))
    agent, asked = agent_for(store, answers=[False])
    assert agent.handle("sabah rutinini sil").text == "Tamam, yapmıyorum."
    assert asked == ["Her gün 08:00'de “günün özetini oku” rutinini sileyim mi?"]
    assert len(store.load()) == 1


@pytest.mark.parametrize(
    ("said", "language"),
    [("stop the morning routine", EN), ("my morning routine is boring, stop the music", EN), ("rutini kapat", TR),
     ("rutin kontrol randevumu iptal et", TR), ("yarın rutin kontrolüm var mı", TR)],
)  # fmt: skip
def test_stopping_something_or_a_routine_check_up_never_deletes_a_routine(tmp_path, said, language):
    store = routines.RoutineStore(tmp_path / "routines.json")
    store.add(Routine("a", EVERY_DAY, 8, 0, "günün özetini oku"))
    rules = routines.routine_rules(language)
    assert [call for route in rules if (call := route(said)) is not None] == []
    assert len(store.load()) == 1


def test_deleting_one_of_several_that_fit_asks_which(tmp_path):
    store = routines.RoutineStore(tmp_path / "routines.json")
    store.add(Routine("a", EVERY_DAY, 21, 0, "hava durumunu söyle"))
    store.add(Routine("b", WEEKDAYS, 7, 0, "hava durumunu söyle"))
    manage = tools_for(store)["manageRoutines"].run
    assert manage({"action": "delete", "name": "hava durumu"}) == (
        "Birden fazla rutin var: 1) hafta içi her gün 07:00'de “hava durumunu söyle”; "
        "2) her gün 21:00'de “hava durumunu söyle”. Hangisini sileyim?"
    )
    assert len(store.load()) == 2
    assert manage({"action": "delete", "index": 2}).startswith("Rutin silindi: her gün 21:00'de")


def test_routines_survive_a_restart_and_a_broken_file_is_not_overwritten(tmp_path):
    path = tmp_path / "routines.json"
    routines.RoutineStore(path).add(Routine("a", WEEKDAYS, 7, 0, "haberleri oku"))
    assert routines.RoutineStore(path).load() == [Routine("a", WEEKDAYS, 7, 0, "haberleri oku")]
    assert json.loads(path.read_text(encoding="utf-8"))["routines"][0]["days"] == [0, 1, 2, 3, 4]
    path.write_text("bozuk", encoding="utf-8")
    add = tools_for(routines.RoutineStore(path))["addRoutine"].run
    with pytest.raises(Exception, match="Rutinlere ulaşamadım"):
        add({"days": ["monday"], "hour": 9, "command": "haberleri oku"})
    assert path.read_text(encoding="utf-8") == "bozuk"


def test_a_routine_cannot_hold_another_routine(tmp_path):
    add = tools_for(routines.RoutineStore(tmp_path / "routines.json"))["addRoutine"]
    arguments = {"days": ["monday"], "hour": 9, "command": "her gün 8'de haberleri oku"}
    assert add.question(arguments) is None
    with pytest.raises(Exception, match="başka bir rutin"):
        add.run(arguments)


def test_english_routine_is_read_back_in_english(tmp_path):
    store = routines.RoutineStore(tmp_path / "routines.json")
    agent, asked = agent_for(store, answers=[True], language=EN)
    assert agent.handle("every night at 9 tell me the weather").text == (
        "OK, routine set: every day at 21:00, “tell me the weather”."
    )
    assert asked == ["Shall I set up this routine: every day at 21:00, “tell me the weather”?"]


class Clock:
    def __init__(self, now):
        self.now = now

    def __call__(self):
        return self.now


def test_the_service_runs_a_due_routine_once_and_skips_times_missed_while_closed(tmp_path):
    store = routines.RoutineStore(tmp_path / "routines.json")
    store.add(Routine("a", EVERY_DAY, 21, 0, "hava durumunu söyle"))
    store.add(Routine("b", EVERY_DAY, 8, 0, "günün özetini oku"))
    ran, clock = [], Clock(NOW)
    service = routines.RoutineService(store, lambda routine: ran.append(routine.command), clock)
    # Started in the evening: the 08:00 routine that passed while Bilge was closed is not run.
    service.start()
    service.stop()
    assert service.check() == [] and ran == []
    assert service.seconds_to_next() == pytest.approx(10)
    clock.now = NOW + timedelta(seconds=15)
    service.check()
    assert ran == ["hava durumunu söyle"]
    clock.now += timedelta(seconds=15)
    service.check()
    assert ran == ["hava durumunu söyle"]


def test_a_routine_deleted_elsewhere_no_longer_runs(tmp_path):
    path = tmp_path / "routines.json"
    store = routines.RoutineStore(path)
    store.add(Routine("a", EVERY_DAY, 21, 0, "hava durumunu söyle"))
    ran, clock = [], Clock(NOW)
    service = routines.RoutineService(store, lambda routine: ran.append(routine.command), clock)
    service.start()
    service.stop()
    # The settings window has a store of its own.
    routines.RoutineStore(path).remove({"a"})
    clock.now = NOW + timedelta(seconds=15)
    assert service.check() == [] and ran == []


def test_a_failing_routine_does_not_stop_the_others(tmp_path):
    store = routines.RoutineStore(tmp_path / "routines.json")
    store.add(Routine("a", EVERY_DAY, 21, 0, "birinci"))
    store.add(Routine("b", EVERY_DAY, 21, 0, "ikinci"))
    ran, clock = [], Clock(NOW)

    def run(routine):
        ran.append(routine.command)
        if routine.command == "birinci":
            raise RuntimeError("boom")

    service = routines.RoutineService(store, run, clock)
    service.start()
    service.stop()
    clock.now = NOW + timedelta(seconds=15)
    service.check()
    assert ran == ["birinci", "ikinci"]


def test_a_routine_carrying_a_listening_mode_command_is_set_up_rather_than_run_now(monkeypatch, tmp_path):
    from bilge import assembly, desktop

    from .test_meeting_tools import Folders, Provider, Recognizer

    monkeypatch.setattr(desktop, "folders", lambda: Folders(tmp_path))
    store = routines.RoutineStore(tmp_path / "routines.json")
    agent = Agent(Provider(), Registry(routines.routine_tools(store, TR)), lambda _: False, TR,
                  rules=routines.routine_rules(TR))  # fmt: skip
    assembly._listening_modes(agent, Recognizer(), TR, tmp_path, announce=lambda _: None)
    for said in ("her pazartesi 10'da toplantıyı kaydet", "her pazartesi 10'da tercüman modunu aç"):
        assert next(call.name for route in agent.rules if (call := route(said))) == "addRoutine"
    assert [call.name for route in agent.rules if (call := route("toplantıyı kaydet"))] == ["startMeetingRecording"]
