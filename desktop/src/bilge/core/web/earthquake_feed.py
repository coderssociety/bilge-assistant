"""Earthquake lists from AFAD (JSON, times in UTC) and Kandilli Observatory (a windows-1254 text table, times in
Türkiye's time), read into one shape. Rows that don't parse are skipped rather than failing the whole list."""

import json
import logging
import math
import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta, timezone
from typing import Any

from bilge.core.web import provinces

log = logging.getLogger(__name__)

# Türkiye has kept UTC+3 all year since 2016.
TURKEY_TIME = timezone(timedelta(hours=3))
# Reports of one earthquake from both sources differ by seconds and a few kilometres.
SAME_EVENT_SECONDS = 90
SAME_EVENT_KM = 50


@dataclass(frozen=True)
class Earthquake:
    id: str
    time: datetime
    latitude: float
    longitude: float
    depth_km: float
    magnitude: float
    place: str

    def distance_km(self, place: provinces.Place) -> float:
        return provinces.distance_km(self.latitude, self.longitude, place.latitude, place.longitude)

    def same_as(self, other: "Earthquake") -> bool:
        if self.id == other.id:
            return True
        close_in_time = abs((self.time - other.time).total_seconds()) <= SAME_EVENT_SECONDS
        return (
            close_in_time
            and provinces.distance_km(self.latitude, self.longitude, other.latitude, other.longitude) <= SAME_EVENT_KM
        )


def parse_afad(body: bytes) -> list[Earthquake]:
    try:
        rows = json.loads(body)
    except ValueError as error:
        raise ValueError("AFAD sent something other than JSON") from error
    if not isinstance(rows, list):
        raise ValueError("AFAD sent an unexpected shape")
    found = [quake for row in rows if isinstance(row, dict) and (quake := _afad_row(row)) is not None]
    return sorted(found, key=lambda q: q.time, reverse=True)


def _afad_row(row: dict[str, Any]) -> Earthquake | None:
    try:
        time = datetime.fromisoformat(str(row["date"])).replace(tzinfo=UTC)
        values = [float(row[key]) for key in ("latitude", "longitude", "depth", "magnitude")]
    except (KeyError, TypeError, ValueError):
        log.debug("Skipped an AFAD row: %r", row)
        return None
    if not all(math.isfinite(v) for v in values):
        return None
    latitude, longitude, depth, magnitude = values
    return Earthquake(f"afad:{row.get('eventID')}", time, latitude, longitude, depth, magnitude, _afad_place(row))


def _afad_place(row: dict[str, Any]) -> str:
    district, province = (str(row.get(key) or "").strip() for key in ("district", "province"))
    # "Ege Denizi - Kuşadası Körfezi - [10.82 km] Menderes (İzmir)": the bracketed offshore distance reads badly.
    location = re.sub(r"\[[^\]]*\]\s*", "", str(row.get("location") or "")).strip(" -")
    # Abroad AFAD still fills in the nearest Turkish district: "Bucharest (Romanya)" comes with Kırklareli, Kofçaz.
    abroad = str(row.get("country") or "Türkiye").strip() not in ("Türkiye", "Turkey", "")
    if district and province and not abroad:
        return f"{district}, {province}"
    return location or province


# 2026.10.25 18:40:56  39.2415   28.0832       11.3      -.-  2.6  -.-   KOZLU-SINDIRGI (BALIKESIR)    İlksel
_KANDILLI_ROW = re.compile(
    r"^(\d{4}\.\d{2}\.\d{2}) (\d{2}:\d{2}:\d{2})\s+(-?[\d.]+)\s+(-?[\d.]+)\s+([\d.]+)\s+"
    r"(\S+)\s+(\S+)\s+(\S+)\s+(.+?)(?:\s{2,}\S.*)?$"
)


def parse_kandilli(body: bytes) -> list[Earthquake]:
    text = body.decode("windows-1254", errors="replace")
    found = []
    for line in text.splitlines():
        match = _KANDILLI_ROW.match(line.strip())
        if match is None:
            continue
        quake = _kandilli_row(match)
        if quake is not None:
            found.append(quake)
    return sorted(found, key=lambda q: q.time, reverse=True)


def _kandilli_row(match: re.Match[str]) -> Earthquake | None:
    day, clock, lat, lon, depth, md, ml, mw, place = match.groups()
    try:
        time = datetime.strptime(f"{day} {clock}", "%Y.%m.%d %H:%M:%S").replace(tzinfo=TURKEY_TIME)
        latitude, longitude, depth_km = float(lat), float(lon), float(depth)
    except ValueError:
        return None
    # Mw when it was worked out, otherwise ML, otherwise MD; "-.-" stands for none.
    magnitude = next((value for value in map(_magnitude, (mw, ml, md)) if value is not None), None)
    if magnitude is None:
        return None
    key = f"kandilli:{day}T{clock}:{lat}:{lon}"
    return Earthquake(key, time.astimezone(UTC), latitude, longitude, depth_km, magnitude, _kandilli_place(place))


def _magnitude(value: str) -> float | None:
    try:
        number = float(value)
    except ValueError:
        return None
    return number if math.isfinite(number) and number > 0 else None


def _kandilli_place(raw: str) -> str:
    """ "KOZLU-SINDIRGI (BALIKESIR)" → "Sindirgi, Balıkesir"; the table is in capitals without Turkish letters, so
    only a province can be given back its own spelling."""
    raw = " ".join(raw.split())
    match = re.fullmatch(r"(.*?)\s*\(([^)]*)\)", raw)
    if match is None:
        alone = provinces.named(raw)
        return alone.name if alone else raw.lower().title()
    area, region = match.group(1), match.group(2)
    province = provinces.named(region)
    region_name = province.name if province else region.lower().title()
    parts = [part.strip() for part in area.split("-") if part.strip()]
    area_name = (parts[-1] if parts else "").lower().title() if province else area.strip(" -").lower().title()
    if area_name and region_name:
        return f"{area_name}, {region_name}" if province else f"{area_name} ({region_name})"
    return area_name or region_name
