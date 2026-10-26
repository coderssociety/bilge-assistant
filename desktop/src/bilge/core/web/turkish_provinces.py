"""Turkey's 81 provinces by plate code, and finding one in a command with its case ending ("İzmir'de",
"Ankara'nın", "Şanlıurfa'ya") or a common short name ("Afyon", "Antep", "Urfa")."""

from dataclasses import dataclass

from bilge.core import text


@dataclass(frozen=True)
class Province:
    plate: int
    name: str


PROVINCES: tuple[Province, ...] = tuple(Province(plate, name) for plate, name in enumerate((
    "Adana", "Adıyaman", "Afyonkarahisar", "Ağrı", "Amasya", "Ankara", "Antalya", "Artvin", "Aydın", "Balıkesir",
    "Bilecik", "Bingöl", "Bitlis", "Bolu", "Burdur", "Bursa", "Çanakkale", "Çankırı", "Çorum", "Denizli",
    "Diyarbakır", "Edirne", "Elazığ", "Erzincan", "Erzurum", "Eskişehir", "Gaziantep", "Giresun", "Gümüşhane",
    "Hakkari", "Hatay", "Isparta", "Mersin", "İstanbul", "İzmir", "Kars", "Kastamonu", "Kayseri", "Kırklareli",
    "Kırşehir", "Kocaeli", "Konya", "Kütahya", "Malatya", "Manisa", "Kahramanmaraş", "Mardin", "Muğla", "Muş",
    "Nevşehir", "Niğde", "Ordu", "Rize", "Sakarya", "Samsun", "Siirt", "Sinop", "Sivas", "Tekirdağ", "Tokat",
    "Trabzon", "Tunceli", "Şanlıurfa", "Uşak", "Van", "Yozgat", "Zonguldak", "Aksaray", "Bayburt", "Karaman",
    "Kırıkkale", "Batman", "Şırnak", "Bartın", "Ardahan", "Iğdır", "Yalova", "Karabük", "Kilis", "Osmaniye", "Düzce",
), start=1))  # fmt: skip

# Folded short names and the old or central-town names people use for the province.
_ALIASES = {
    "afyon": 3, "antep": 27, "maras": 46, "urfa": 63, "icel": 33, "izmit": 41, "adapazari": 54, "antakya": 31,
}  # fmt: skip
# Folded case endings and suffixes that may follow a name once the apostrophe is dropped.
_ENDINGS = frozenset({
    "", "da", "de", "ta", "te", "dan", "den", "tan", "ten", "in", "nin", "un", "nun", "a", "e", "ya", "ye", "na",
    "ne", "i", "yi", "u", "yu", "daki", "deki", "taki", "teki", "li", "lu", "s",
})  # fmt: skip
# "bulur musun" folds to "Muş'un"; spelled without "ş" it is the question particle.
_QUESTION_PARTICLES = frozenset({"musun", "musunuz"})
_BY_PLATE = {province.plate: province for province in PROVINCES}
_FOLDED = sorted(
    [(text.folded(p.name), p.plate) for p in PROVINCES] + list(_ALIASES.items()), key=lambda pair: -len(pair[0])
)


def by_plate(plate: int) -> Province | None:
    return _BY_PLATE.get(plate)


def find(command: str) -> Province | None:
    """The first province named in the command."""
    for word in text.folded(without_question_particles(command)).split():
        found = _match(word)
        if found is not None:
            return found
    return None


def without_question_particles(command: str) -> str:
    return " ".join(word for word in text.normalized(command).split() if word not in _QUESTION_PARTICLES)


def _match(word: str) -> Province | None:
    for folded_name, plate in _FOLDED:
        if word.startswith(folded_name) and word[len(folded_name) :] in _ENDINGS:
            return _BY_PLATE[plate]
    return None
