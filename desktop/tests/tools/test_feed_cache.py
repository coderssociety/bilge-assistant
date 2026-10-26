from bilge.tools.feed_cache import TimedCache


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now


def test_values_are_kept_until_they_are_old():
    clock, loads = Clock(), []
    cache = TimedCache(clock)
    assert cache.get("k", 60, lambda: loads.append(1) or ["a"]) == ["a"]
    clock.now = 30
    assert cache.get("k", 60, lambda: loads.append(1) or ["b"]) == ["a"]
    clock.now = 61
    assert cache.get("k", 60, lambda: loads.append(1) or ["c"]) == ["c"]
    assert len(loads) == 2


def test_an_empty_answer_is_asked_again_next_time():
    cache, loads = TimedCache(Clock()), []
    answers = iter([[], ["station"]])
    assert cache.get("k", 3600, lambda: loads.append(1) or next(answers)) == []
    assert cache.get("k", 3600, lambda: loads.append(1) or next(answers)) == ["station"]
    assert len(loads) == 2
