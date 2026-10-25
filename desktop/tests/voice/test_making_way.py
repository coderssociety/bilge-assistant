from bilge.assembly import _making_way


def test_the_player_makes_way_from_the_wake_word_until_bilge_has_answered():
    calls, events = [], []

    class Recorder:
        def set_busy(self, on):
            calls.append(on)

        def stop(self):
            calls.append("stop")

    handle = _making_way(Recorder(), lambda kind, text: events.append((kind, text)))
    for status in ("awake", "thinking", "speaking", "listening", "off"):
        handle("status", status)
    handle("reply", "Power FM açıldı.")
    assert calls == [True, True, True, False, "stop", False]
    assert events[-1] == ("reply", "Power FM açıldı.") and len(events) == 6
