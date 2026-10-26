"""The 81 province centres of Türkiye with their coordinates, for "İzmir'de deprem var mı" and how far an earthquake
was from the user's city."""

import math
from dataclasses import dataclass

from bilge.core.text import folded
from bilge.core.web import spoken_names, turkish_provinces

EARTH_RADIUS_KM = 6371.0


@dataclass(frozen=True)
class Place:
    name: str
    latitude: float
    longitude: float


PROVINCES = tuple(Place(name, lat, lon) for name, lat, lon in (
    ("Adana", 37.00, 35.32), ("Adıyaman", 37.76, 38.28), ("Afyonkarahisar", 38.76, 30.54), ("Ağrı", 39.72, 43.05),
    ("Amasya", 40.65, 35.83), ("Ankara", 39.93, 32.86), ("Antalya", 36.90, 30.70), ("Artvin", 41.18, 41.82),
    ("Aydın", 37.85, 27.84), ("Balıkesir", 39.65, 27.88), ("Bilecik", 40.14, 29.98), ("Bingöl", 38.88, 40.50),
    ("Bitlis", 38.40, 42.11), ("Bolu", 40.73, 31.61), ("Burdur", 37.72, 30.29), ("Bursa", 40.19, 29.06),
    ("Çanakkale", 40.15, 26.41), ("Çankırı", 40.60, 33.62), ("Çorum", 40.55, 34.95), ("Denizli", 37.78, 29.09),
    ("Diyarbakır", 37.91, 40.24), ("Edirne", 41.68, 26.56), ("Elazığ", 38.67, 39.22), ("Erzincan", 39.75, 39.49),
    ("Erzurum", 39.90, 41.27), ("Eskişehir", 39.78, 30.52), ("Gaziantep", 37.07, 37.38), ("Giresun", 40.91, 38.39),
    ("Gümüşhane", 40.46, 39.48), ("Hakkari", 37.58, 43.74), ("Hatay", 36.20, 36.16), ("Isparta", 37.76, 30.55),
    ("Mersin", 36.80, 34.63), ("İstanbul", 41.01, 28.98), ("İzmir", 38.42, 27.14), ("Kars", 40.60, 43.10),
    ("Kastamonu", 41.38, 33.78), ("Kayseri", 38.73, 35.48), ("Kırklareli", 41.73, 27.22), ("Kırşehir", 39.15, 34.16),
    ("Kocaeli", 40.77, 29.92), ("Konya", 37.87, 32.48), ("Kütahya", 39.42, 29.98), ("Malatya", 38.35, 38.31),
    ("Manisa", 38.61, 27.43), ("Kahramanmaraş", 37.58, 36.94), ("Mardin", 37.31, 40.74), ("Muğla", 37.22, 28.36),
    ("Muş", 38.74, 41.49), ("Nevşehir", 38.62, 34.71), ("Niğde", 37.97, 34.68), ("Ordu", 40.98, 37.88),
    ("Rize", 41.02, 40.52), ("Sakarya", 40.78, 30.40), ("Samsun", 41.29, 36.33), ("Siirt", 37.93, 41.94),
    ("Sinop", 42.03, 35.15), ("Sivas", 39.75, 37.02), ("Tekirdağ", 40.98, 27.51), ("Tokat", 40.31, 36.55),
    ("Trabzon", 41.00, 39.72), ("Tunceli", 39.11, 39.55), ("Şanlıurfa", 37.17, 38.79), ("Uşak", 38.68, 29.41),
    ("Van", 38.49, 43.38), ("Yozgat", 39.82, 34.81), ("Zonguldak", 41.45, 31.79), ("Aksaray", 38.37, 34.03),
    ("Bayburt", 40.26, 40.23), ("Karaman", 37.18, 33.22), ("Kırıkkale", 39.85, 33.51), ("Batman", 37.88, 41.13),
    ("Şırnak", 37.52, 42.46), ("Bartın", 41.63, 32.34), ("Ardahan", 41.11, 42.70), ("Iğdır", 39.92, 44.05),
    ("Yalova", 40.65, 29.27), ("Karabük", 41.20, 32.62), ("Kilis", 36.72, 37.12), ("Osmaniye", 37.07, 36.25),
    ("Düzce", 40.84, 31.16),
))  # fmt: skip

_BY_NAME = {folded(place.name): place for place in PROVINCES}
# Names people use for the centre rather than the province.
_ALIASES = {
    "afyon": "Afyonkarahisar", "maraş": "Kahramanmaraş", "urfa": "Şanlıurfa", "antep": "Gaziantep",
    "izmit": "Kocaeli", "adapazarı": "Sakarya", "antakya": "Hatay", "içel": "Mersin",
}  # fmt: skip
_BY_ALIAS = {folded(alias): _BY_NAME[folded(name)] for alias, name in _ALIASES.items()}


def named(name: str) -> Place | None:
    """The province a city name stands for, however it is spelled ("izmir", "İzmir", "Maraş")."""
    key = folded(name)
    return _BY_NAME.get(key) or _BY_ALIAS.get(key)


def mentioned(command: str) -> Place | None:
    """A province said in a command: "İzmir'de deprem var mı" → İzmir."""
    names = [(place.name, place) for place in PROVINCES]
    names += list(_BY_ALIAS.items())
    return spoken_names.find(turkish_provinces.without_question_particles(command), names)


def distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance (haversine)."""
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    d_phi, d_lambda = phi2 - phi1, math.radians(lon2 - lon1)
    a = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    return 2 * EARTH_RADIUS_KM * math.asin(min(1.0, math.sqrt(a)))
