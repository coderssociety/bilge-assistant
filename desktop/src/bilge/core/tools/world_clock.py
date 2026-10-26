"""The time in another city or country ("Tokyo'da saat kaç", "New York ile aramızda kaç saat fark var", "what time is
it in London"), from a built-in table of Turkish and English place names and their IANA time zones."""

from dataclasses import dataclass
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from bilge.core.text import folded


@dataclass(frozen=True)
class Place:
    zone: str
    turkish: str
    english: str
    # Folded, possibly several words ("new york").
    names: tuple[str, ...] = ()


@dataclass(frozen=True)
class WorldClockRequest:
    # One place, or two for the difference between them ("Tokyo ile New York arasında").
    places: tuple[Place, ...]
    difference: bool


def _place(zone: str, turkish: str, english: str, *aliases: str) -> Place:
    names = {folded(turkish), folded(english), *aliases}
    return Place(zone, turkish, english, tuple(sorted(names)))


PLACES: tuple[Place, ...] = (
    _place("Europe/Istanbul", "İstanbul", "Istanbul"),
    _place("Europe/Istanbul", "Ankara", "Ankara"),
    _place("Europe/Istanbul", "İzmir", "Izmir"),
    _place("Europe/Istanbul", "Türkiye", "Turkey"),
    _place("Asia/Nicosia", "Lefkoşa", "Nicosia"),
    _place("Asia/Nicosia", "Kıbrıs", "Cyprus", "kktc"),
    _place("Asia/Tokyo", "Tokyo", "Tokyo"),
    _place("Asia/Tokyo", "Japonya", "Japan"),
    _place("Asia/Seoul", "Seul", "Seoul"),
    _place("Asia/Seoul", "Güney Kore", "South Korea", "kore", "korea"),
    _place("Asia/Shanghai", "Pekin", "Beijing"),
    _place("Asia/Shanghai", "Şanghay", "Shanghai", "sangay"),
    _place("Asia/Shanghai", "Çin", "China"),
    _place("Asia/Hong_Kong", "Hong Kong", "Hong Kong"),
    _place("Asia/Taipei", "Taipei", "Taipei"),
    _place("Asia/Taipei", "Tayvan", "Taiwan"),
    _place("Asia/Singapore", "Singapur", "Singapore"),
    _place("Asia/Bangkok", "Bangkok", "Bangkok"),
    _place("Asia/Bangkok", "Tayland", "Thailand"),
    _place("Asia/Jakarta", "Cakarta", "Jakarta"),
    _place("Asia/Jakarta", "Endonezya", "Indonesia"),
    _place("Asia/Manila", "Manila", "Manila"),
    _place("Asia/Manila", "Filipinler", "Philippines"),
    _place("Asia/Kolkata", "Yeni Delhi", "New Delhi", "delhi"),
    _place("Asia/Kolkata", "Mumbai", "Mumbai", "bombay"),
    _place("Asia/Kolkata", "Hindistan", "India"),
    _place("Asia/Karachi", "Karaçi", "Karachi"),
    _place("Asia/Karachi", "İslamabad", "Islamabad"),
    _place("Asia/Karachi", "Pakistan", "Pakistan"),
    _place("Asia/Kabul", "Kabil", "Kabul"),
    _place("Asia/Kabul", "Afganistan", "Afghanistan"),
    _place("Asia/Tehran", "Tahran", "Tehran"),
    _place("Asia/Tehran", "İran", "Iran"),
    _place("Asia/Baghdad", "Bağdat", "Baghdad"),
    _place("Asia/Baghdad", "Irak", "Iraq"),
    _place("Asia/Riyadh", "Riyad", "Riyadh"),
    _place("Asia/Riyadh", "Mekke", "Mecca"),
    _place("Asia/Riyadh", "Medine", "Medina"),
    _place("Asia/Riyadh", "Suudi Arabistan", "Saudi Arabia"),
    _place("Asia/Qatar", "Doha", "Doha"),
    _place("Asia/Qatar", "Katar", "Qatar"),
    _place("Asia/Dubai", "Dubai", "Dubai", "dubay"),
    _place("Asia/Dubai", "Abu Dabi", "Abu Dhabi"),
    _place("Asia/Dubai", "BAE", "the United Arab Emirates", "birlesik arap emirlikleri", "united arab emirates", "uae"),
    _place("Asia/Jerusalem", "Kudüs", "Jerusalem"),
    _place("Asia/Jerusalem", "Tel Aviv", "Tel Aviv"),
    _place("Asia/Jerusalem", "İsrail", "Israel"),
    _place("Asia/Amman", "Amman", "Amman"),
    _place("Asia/Amman", "Ürdün", "Jordan"),
    _place("Asia/Beirut", "Beyrut", "Beirut"),
    _place("Asia/Beirut", "Lübnan", "Lebanon"),
    _place("Asia/Damascus", "Şam", "Damascus"),
    _place("Asia/Damascus", "Suriye", "Syria"),
    _place("Asia/Baku", "Bakü", "Baku"),
    _place("Asia/Baku", "Azerbaycan", "Azerbaijan"),
    _place("Asia/Tbilisi", "Tiflis", "Tbilisi"),
    _place("Asia/Tbilisi", "Gürcistan", "Georgia"),
    _place("Asia/Yerevan", "Erivan", "Yerevan"),
    _place("Asia/Yerevan", "Ermenistan", "Armenia"),
    _place("Asia/Tashkent", "Taşkent", "Tashkent"),
    _place("Asia/Tashkent", "Özbekistan", "Uzbekistan"),
    _place("Asia/Almaty", "Almatı", "Almaty"),
    _place("Asia/Almaty", "Astana", "Astana"),
    _place("Asia/Almaty", "Kazakistan", "Kazakhstan"),
    _place("Asia/Bishkek", "Bişkek", "Bishkek"),
    _place("Asia/Bishkek", "Kırgızistan", "Kyrgyzstan"),
    _place("Asia/Ashgabat", "Aşkabat", "Ashgabat"),
    _place("Asia/Ashgabat", "Türkmenistan", "Turkmenistan"),
    _place("Europe/London", "Londra", "London"),
    _place("Europe/London", "İngiltere", "England", "birlesik krallik", "united kingdom", "uk", "britanya", "britain"),
    _place("Europe/Dublin", "Dublin", "Dublin"),
    _place("Europe/Dublin", "İrlanda", "Ireland"),
    _place("Europe/Lisbon", "Lizbon", "Lisbon"),
    _place("Europe/Lisbon", "Portekiz", "Portugal"),
    _place("Europe/Madrid", "Madrid", "Madrid"),
    _place("Europe/Madrid", "Barselona", "Barcelona"),
    _place("Europe/Madrid", "İspanya", "Spain"),
    _place("Europe/Paris", "Paris", "Paris"),
    _place("Europe/Paris", "Fransa", "France"),
    _place("Europe/Brussels", "Brüksel", "Brussels"),
    _place("Europe/Brussels", "Belçika", "Belgium"),
    _place("Europe/Amsterdam", "Amsterdam", "Amsterdam"),
    _place("Europe/Amsterdam", "Hollanda", "Netherlands"),
    _place("Europe/Berlin", "Berlin", "Berlin"),
    _place("Europe/Berlin", "Münih", "Munich"),
    _place("Europe/Berlin", "Frankfurt", "Frankfurt"),
    _place("Europe/Berlin", "Hamburg", "Hamburg"),
    _place("Europe/Berlin", "Köln", "Cologne"),
    _place("Europe/Berlin", "Almanya", "Germany"),
    _place("Europe/Zurich", "Zürih", "Zurich"),
    _place("Europe/Zurich", "Cenevre", "Geneva"),
    _place("Europe/Zurich", "İsviçre", "Switzerland"),
    _place("Europe/Vienna", "Viyana", "Vienna"),
    _place("Europe/Vienna", "Avusturya", "Austria"),
    _place("Europe/Rome", "Roma", "Rome"),
    _place("Europe/Rome", "Milano", "Milan"),
    _place("Europe/Rome", "İtalya", "Italy"),
    _place("Europe/Prague", "Prag", "Prague"),
    _place("Europe/Prague", "Çekya", "Czechia"),
    _place("Europe/Warsaw", "Varşova", "Warsaw"),
    _place("Europe/Warsaw", "Polonya", "Poland"),
    _place("Europe/Budapest", "Budapeşte", "Budapest"),
    _place("Europe/Budapest", "Macaristan", "Hungary"),
    _place("Europe/Copenhagen", "Kopenhag", "Copenhagen"),
    _place("Europe/Copenhagen", "Danimarka", "Denmark"),
    _place("Europe/Stockholm", "Stockholm", "Stockholm"),
    _place("Europe/Stockholm", "İsveç", "Sweden"),
    _place("Europe/Oslo", "Oslo", "Oslo"),
    _place("Europe/Oslo", "Norveç", "Norway"),
    _place("Europe/Helsinki", "Helsinki", "Helsinki"),
    _place("Europe/Helsinki", "Finlandiya", "Finland"),
    _place("Atlantic/Reykjavik", "Reykjavik", "Reykjavik"),
    _place("Atlantic/Reykjavik", "İzlanda", "Iceland"),
    _place("Europe/Athens", "Atina", "Athens"),
    _place("Europe/Athens", "Selanik", "Thessaloniki"),
    _place("Europe/Athens", "Yunanistan", "Greece"),
    _place("Europe/Sofia", "Sofya", "Sofia"),
    _place("Europe/Sofia", "Bulgaristan", "Bulgaria"),
    _place("Europe/Bucharest", "Bükreş", "Bucharest"),
    _place("Europe/Bucharest", "Romanya", "Romania"),
    _place("Europe/Belgrade", "Belgrad", "Belgrade"),
    _place("Europe/Belgrade", "Sırbistan", "Serbia"),
    _place("Europe/Sarajevo", "Saraybosna", "Sarajevo"),
    _place("Europe/Sarajevo", "Bosna Hersek", "Bosnia", "bosna"),
    _place("Europe/Skopje", "Üsküp", "Skopje"),
    _place("Europe/Skopje", "Makedonya", "North Macedonia", "macedonia"),
    _place("Europe/Kiev", "Kiev", "Kyiv"),
    _place("Europe/Kiev", "Ukrayna", "Ukraine"),
    _place("Europe/Moscow", "Moskova", "Moscow"),
    _place("Europe/Moscow", "Sankt Peterburg", "Saint Petersburg"),
    _place("Europe/Moscow", "Rusya", "Russia"),
    _place("Africa/Cairo", "Kahire", "Cairo"),
    _place("Africa/Cairo", "Mısır", "Egypt"),
    _place("Africa/Casablanca", "Kazablanka", "Casablanca"),
    _place("Africa/Casablanca", "Fas", "Morocco"),
    _place("Africa/Tunis", "Tunus", "Tunisia", "tunis"),
    _place("Africa/Lagos", "Lagos", "Lagos"),
    _place("Africa/Lagos", "Nijerya", "Nigeria"),
    _place("Africa/Nairobi", "Nairobi", "Nairobi"),
    _place("Africa/Nairobi", "Kenya", "Kenya"),
    _place("Africa/Johannesburg", "Johannesburg", "Johannesburg"),
    _place("Africa/Johannesburg", "Cape Town", "Cape Town"),
    _place("Africa/Johannesburg", "Güney Afrika", "South Africa"),
    _place("America/New_York", "New York", "New York", "nevyork"),
    _place("America/New_York", "Washington", "Washington"),
    _place("America/New_York", "Boston", "Boston"),
    _place("America/New_York", "Miami", "Miami"),
    _place("America/New_York", "Amerika", "the United States", "abd", "america", "usa", "united states"),
    _place("America/Chicago", "Chicago", "Chicago", "sikago"),
    _place("America/Chicago", "Houston", "Houston"),
    _place("America/Chicago", "Dallas", "Dallas"),
    _place("America/Denver", "Denver", "Denver"),
    _place("America/Los_Angeles", "Los Angeles", "Los Angeles"),
    _place("America/Los_Angeles", "San Francisco", "San Francisco"),
    _place("America/Los_Angeles", "Seattle", "Seattle"),
    _place("America/Los_Angeles", "Las Vegas", "Las Vegas"),
    _place("Pacific/Honolulu", "Hawaii", "Hawaii", "havai", "honolulu"),
    _place("America/Toronto", "Toronto", "Toronto"),
    _place("America/Toronto", "Montreal", "Montreal"),
    _place("America/Toronto", "Ottawa", "Ottawa"),
    _place("America/Toronto", "Kanada", "Canada"),
    _place("America/Vancouver", "Vancouver", "Vancouver"),
    _place("America/Mexico_City", "Meksiko", "Mexico City"),
    _place("America/Mexico_City", "Meksika", "Mexico"),
    _place("America/Bogota", "Bogota", "Bogota"),
    _place("America/Bogota", "Kolombiya", "Colombia"),
    _place("America/Lima", "Lima", "Lima"),
    _place("America/Lima", "Peru", "Peru"),
    _place("America/Santiago", "Santiago", "Santiago"),
    _place("America/Santiago", "Şili", "Chile"),
    _place("America/Sao_Paulo", "São Paulo", "Sao Paulo"),
    _place("America/Sao_Paulo", "Rio de Janeiro", "Rio de Janeiro"),
    _place("America/Sao_Paulo", "Brezilya", "Brazil"),
    _place("America/Argentina/Buenos_Aires", "Buenos Aires", "Buenos Aires"),
    _place("America/Argentina/Buenos_Aires", "Arjantin", "Argentina"),
    _place("Australia/Sydney", "Sidney", "Sydney"),
    _place("Australia/Sydney", "Avustralya", "Australia"),
    _place("Australia/Melbourne", "Melbourne", "Melbourne"),
    _place("Australia/Perth", "Perth", "Perth"),
    _place("Pacific/Auckland", "Auckland", "Auckland"),
    _place("Pacific/Auckland", "Yeni Zelanda", "New Zealand"),
)  # fmt: skip

_BY_NAME: dict[tuple[str, ...], Place] = {tuple(name.split()): place for place in PLACES for name in place.names}
_LONGEST_NAME = max(len(words) for words in _BY_NAME)
# Case endings joined to the name once the apostrophe is dropped ("Tokyo'da" → "tokyoda", "New York'la"), folded.
_SUFFIXES = (
    "da", "de", "ta", "te", "nda", "nde", "la", "le", "yla", "yle", "ya", "ye", "a", "e", "in", "nin", "un", "nun",
    "yin", "yun", "i", "yi", "u", "yu", "dan", "den", "tan", "ten", "ndan", "nden", "daki", "deki", "taki", "teki",
)  # fmt: skip
_TIME_WORDS = frozenset({"saat", "saati", "time"})
_DIFFERENCE_WORDS = frozenset({"fark", "farki", "ileride", "geride", "difference", "ahead", "behind"})
_ALLOWED = _TIME_WORDS | _DIFFERENCE_WORDS | frozenset({
    "kac", "oldu", "ne", "nedir", "simdi", "su", "an", "acaba", "orada", "ile", "aramizda", "aramizdaki",
    "arasinda", "arasindaki", "var", "bizden", "benden", "ileri", "geri", "what", "is", "it", "in", "whats", "the",
    "current", "now", "right", "between", "us", "me", "and", "here", "how", "many", "hours", "far", "with",
    "local", "of", "from", "there",
})  # fmt: skip


def parse(text: str) -> WorldClockRequest | None:
    """None unless the request is only about the time somewhere, or the difference."""
    words = folded(text).split()
    places: list[Place] = []
    rest: list[str] = []
    index = 0
    while index < len(words):
        found = _place_at(words, index)
        if found is None:
            rest.append(words[index])
            index += 1
            continue
        places.append(found[0])
        index += found[1]
    if not places or len(places) > 2 or not all(word in _ALLOWED for word in rest):
        return None
    difference = any(word in _DIFFERENCE_WORDS for word in rest)
    if not difference and (len(places) > 1 or not any(word in _TIME_WORDS for word in rest)):
        return None
    return WorldClockRequest(tuple(places), difference)


def place_named(text: str) -> Place | None:
    """A place from the table, or an IANA zone the model named ("America/Phoenix")."""
    words = folded(text).split()
    found = _place_at(words, 0) if words else None
    if found is not None and found[1] == len(words):
        return found[0]
    zone = text.strip()
    if "/" not in zone:
        return None
    try:
        ZoneInfo(zone)
    except (ZoneInfoNotFoundError, ValueError):
        return None
    city = zone.rsplit("/", 1)[-1].replace("_", " ")
    return Place(zone, city, city)


def time_there(place: Place, now: datetime) -> datetime:
    """`now` must carry its zone."""
    return now.astimezone(ZoneInfo(place.zone))


def difference(place: Place, now: datetime, reference: Place | None = None) -> timedelta:
    """How far `place` is ahead of `reference` (negative when behind); without one, of the zone `now` is in."""
    here = time_there(reference, now) if reference is not None else now
    there = time_there(place, now)
    return (there.utcoffset() or timedelta()) - (here.utcoffset() or timedelta())


def _place_at(words: list[str], index: int) -> tuple[Place, int] | None:
    for size in range(min(_LONGEST_NAME, len(words) - index), 0, -1):
        *head, last = words[index : index + size]
        exact = _BY_NAME.get((*head, last))
        if exact is not None:
            return exact, size
        for suffix in _SUFFIXES:
            if last.endswith(suffix) and len(last) > len(suffix) + 1:
                place = _BY_NAME.get((*head, last[: -len(suffix)]))
                if place is not None:
                    return place, size
    return None
