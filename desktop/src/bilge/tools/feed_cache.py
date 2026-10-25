"""Keeps the answers of public data services for a while: scores, quotes and earthquake lists change by the minute,
not by the second, and a follow-up question shouldn't wait on the network again."""

import threading
import time
from collections.abc import Callable
from typing import Any


class TimedCache:
    """Values by key until they are `seconds` old. Failures aren't kept, so the next question tries again."""

    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._clock = clock
        self._values: dict[str, tuple[float, Any]] = {}
        self._lock = threading.Lock()

    def get(self, key: str, seconds: float, load: Callable[[], Any]) -> Any:
        now = self._clock()
        with self._lock:
            kept = self._values.get(key)
        if kept is not None and now - kept[0] < seconds:
            return kept[1]
        value = load()
        with self._lock:
            self._values[key] = (now, value)
        return value
