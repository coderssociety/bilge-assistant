"""Decides which earthquakes near the user are said without being asked: strong enough, close enough, new enough,
and each only once, even when the two sources report it under different ids."""

import threading
from collections.abc import Iterable
from datetime import datetime, timedelta

from bilge.core.web.earthquake_feed import Earthquake
from bilge.core.web.provinces import Place

ALERT_MAGNITUDE = 4.0
ALERT_RADIUS_KM = 150
POLL_SECONDS = 120
MAX_RETRY_SECONDS = 30 * 60
# Right after Bilge starts, an earthquake from before this is old news rather than an alert.
STARTUP_AGE = timedelta(minutes=15)
# AFAD may publish an earthquake minutes late; after an hour it is no longer worth interrupting for.
MAX_AGE = timedelta(hours=1)
# Kept as long as a source may still list them.
_REMEMBERED = timedelta(days=1)


def retry_delay(failures: int) -> float:
    """Seconds until the next poll: the usual interval, doubled for each failure in a row, up to half an hour."""
    if failures <= 0:
        return POLL_SECONDS
    return min(POLL_SECONDS * 2**failures, MAX_RETRY_SECONDS)


class Announced:
    """The earthquakes already considered while Bilge runs; shared by the watchers a restart builds one after another,
    so saving the settings doesn't announce the same earthquake again."""

    def __init__(self) -> None:
        self._seen: list[Earthquake] = []
        self._lock = threading.Lock()

    def take_new(self, quakes: Iterable[Earthquake], now: datetime) -> list[Earthquake]:
        """Remembers the given earthquakes and returns those not seen before."""
        new = []
        with self._lock:
            self._seen = [q for q in self._seen if now - q.time <= _REMEMBERED]
            for quake in quakes:
                if not any(quake.same_as(seen) for seen in self._seen):
                    self._seen.append(quake)
                    new.append(quake)
        return new


class EarthquakeAlerts:
    def __init__(
        self,
        home: Place,
        announced: Announced | None = None,
        magnitude: float = ALERT_MAGNITUDE,
        radius_km: float = ALERT_RADIUS_KM,
    ) -> None:
        self.home = home
        self._announced = announced or Announced()
        self._magnitude = magnitude
        self._radius_km = radius_km
        self._started = False

    def due(self, quakes: Iterable[Earthquake], now: datetime) -> list[Earthquake]:
        """Oldest first. Every nearby strong earthquake is remembered, also those too old to say, so they don't
        come up once the startup window has passed."""
        oldest = STARTUP_AGE if not self._started else MAX_AGE
        self._started = True
        nearby = [q for q in quakes if q.magnitude >= self._magnitude and q.distance_km(self.home) <= self._radius_km]
        new = self._announced.take_new(sorted(nearby, key=lambda q: q.time), now)
        return [q for q in new if now - q.time <= oldest]
