import json
from datetime import datetime, timedelta

from bilge.core.language import AssistantLanguage
from bilge.tools.desktop import timers

TR, EN = AssistantLanguage.TURKISH, AssistantLanguage.ENGLISH
NOW = datetime(2026, 10, 15, 14, 0)


def setup(store=None, language=TR, announced=None):
    clock = {"now": NOW}
    service = timers.TimerService((announced if announced is not None else []).append, language,
                                  clock=lambda: clock["now"], store=store)  # fmt: skip
    tools = {tool.name: tool for tool in timers.timer_tools(service, language, clock=lambda: clock["now"])}
    return service, tools, clock


def test_one_timer_is_cancelled_by_its_label_and_the_others_keep_running():
    service, tools, _ = setup()
    tools["setTimer"].run({"minutes": 5, "label": "çay"})
    tools["setTimer"].run({"hour": 18, "label": "yumurta"})
    manage = tools["manageTimers"].run
    assert manage({"action": "cancel", "label": "çayın zamanlayıcısı"}) == "Saat 14:05 çay zamanlayıcısı iptal edildi."
    assert [t.label for t in service.timers] == ["yumurta"]
    assert manage({"action": "cancel", "label": "makarna"}) == (
        "Öyle bir zamanlayıcı bulamadım. Kurulu olanlar: 18:00 yumurta"
    )


def test_cancelling_without_a_name_takes_the_only_one_or_asks_which():
    service, tools, _ = setup()
    manage = tools["manageTimers"].run
    assert manage({"action": "cancel"}) == "İptal edilecek zamanlayıcı yoktu."
    tools["setTimer"].run({"minutes": 10})
    tools["setTimer"].run({"minutes": 20, "label": "su"})
    assert manage({"action": "cancel"}) == (
        "Birden fazla zamanlayıcı var: 1) 14:10; 2) 14:20 su. Hangisini iptal edeyim?"
    )
    assert len(service.timers) == 2
    assert manage({"action": "cancel", "index": 2}) == "Saat 14:20 su zamanlayıcısı iptal edildi."
    assert manage({"action": "cancel"}) == "Saat 14:10 zamanlayıcısı iptal edildi."
    assert service.timers == []


def test_time_left_for_one_or_every_timer():
    _, tools, clock = setup()
    manage = tools["manageTimers"].run
    assert manage({"action": "remaining"}) == "Kurulu zamanlayıcı yok."
    tools["setTimer"].run({"minutes": 5, "label": "çay"})
    clock["now"] = NOW + timedelta(seconds=30)
    assert manage({"action": "remaining"}) == "Saat 14:05 çay zamanlayıcısına 4 dakika 30 saniye kaldı."
    tools["setTimer"].run({"hour": 16})
    assert manage({"action": "remaining"}) == "Kalan süreler: 14:05 çay: 4 dakika 30 saniye; 16:00: 2 saat."
    assert manage({"action": "remaining", "label": "çay"}).endswith("4 dakika 30 saniye kaldı.")


def test_english_time_left():
    _, tools, _ = setup(language=EN)
    tools["setTimer"].run({"minutes": 90})
    assert tools["manageTimers"].run({"action": "remaining"}) == "1 h 30 min left on the 15:30 timer."


def test_quarter_to_without_part_of_day_takes_the_next_one():
    _, tools, _ = setup()
    refined = tools["setTimer"].refine({}, "8'e çeyrek kala alarm kur")
    assert (refined["hour"], refined["minute"]) == (19, 45)
    assert tools["setTimer"].refine({}, "3 çeyrek saat sonra uyar")["minutes"] == 45


def test_pending_timers_survive_a_restart_and_missed_ones_are_announced(tmp_path):
    store = tmp_path / "timers.json"
    service, tools, _ = setup(store)
    tools["setTimer"].run({"minutes": 5, "label": "çay"})
    tools["setTimer"].run({"hour": 18})
    assert len(json.loads(store.read_text(encoding="utf-8"))["timers"]) == 2

    announced = []
    clock = {"now": NOW + timedelta(minutes=30)}
    restarted = timers.TimerService(announced.append, TR, clock=lambda: clock["now"], store=store)
    missed = restarted.restore()
    assert [t.label for t in missed] == ["çay"]
    assert announced == ["Bilge kapalıyken şu zamanlayıcıların zamanı geçti: 14:05 çay."]
    assert [f"{t.fires_at:%H:%M}" for t in restarted.timers] == ["18:00"]
    assert len(json.loads(store.read_text(encoding="utf-8"))["timers"]) == 1
    restarted.cancel_all()
    assert json.loads(store.read_text(encoding="utf-8")) == {"timers": []}


def test_an_unreadable_timer_file_starts_empty(tmp_path):
    store = tmp_path / "timers.json"
    store.write_text("{bozuk", encoding="utf-8")
    service, _, _ = setup(store)
    assert service.restore() == []
    assert service.timers == []
