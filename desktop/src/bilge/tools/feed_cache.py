"""Fetching the JSON of public data services, and keeping answers for a while: scores, quotes and earthquake lists
change by the minute, not by the second, and a follow-up question shouldn't wait on the network again."""

import json
import threading
import time
from collections.abc import Callable
from typing import Any

from bilge.core.language import AssistantLanguage
from bilge.tools import web_fetch


def get_json(url: str, language: AssistantLanguage) -> Any:
    response = web_fetch.get(url, language)
    if response.status != 200:
        raise web_fetch.WebFetchError(web_fetch.Reason.STATUS, response.status)
    try:
        return json.loads(response.body)
    except ValueError as error:
        raise web_fetch.WebFetchError(web_fetch.Reason.UNEXPECTED) from error


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
