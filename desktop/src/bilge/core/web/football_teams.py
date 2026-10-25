"""Süper Lig clubs by the names Turkish fans use ("GS", "Cimbom", "Fener", "BJK"), and the names ESPN gives them
("Fenerbahce", "Istanbul Basaksehir"). Clubs come and go with promotion, so a club missing here still shows up under
ESPN's own name."""

from dataclasses import dataclass

from bilge.core.text import folded
from bilge.core.web import spoken_names


@dataclass(frozen=True)
class Team:
    name: str
    # ESPN's names for it, any spelling.
    espn: tuple[str, ...]
    aliases: tuple[str, ...] = ()


TEAMS = (
    Team("Galatasaray", ("Galatasaray",), ("GS", "Cimbom", "Cimbombom", "Aslan")),
    Team("Fenerbahçe", ("Fenerbahce",), ("Fener", "FB", "Kanarya")),
    Team("Beşiktaş", ("Besiktas",), ("BJK", "Kara Kartal", "Kartal")),
    Team("Trabzonspor", ("Trabzonspor",), ("Trabzon", "TS", "Bordo Mavi")),
    Team("Başakşehir", ("Istanbul Basaksehir", "Basaksehir"), ("İstanbul Başakşehir", "İBFK")),
    Team("Göztepe", ("Goztepe",)),
    Team("Kasımpaşa", ("Kasimpasa",)),
    Team("Konyaspor", ("Konyaspor",), ("Konya",)),
    Team("Samsunspor", ("Samsunspor",), ("Samsun",)),
    Team("Kocaelispor", ("Kocaelispor",), ("Kocaeli",)),
    Team("Alanyaspor", ("Alanyaspor",), ("Alanya",)),
    Team("Çaykur Rizespor", ("Caykur Rizespor", "Rizespor"), ("Rizespor", "Rize")),
    Team("Eyüpspor", ("Eyupspor",), ("Eyüp",)),
    Team("Gaziantep FK", ("Gaziantep FK", "Gaziantep"), ("Gaziantep", "Antep")),
    Team("Gençlerbirliği", ("Genclerbirligi",), ("Gençler",)),
    Team("Erzurumspor", ("Erzurum BB", "Erzurumspor", "BB Erzurumspor"), ("Erzurum",)),
    Team("Amedspor", ("Amed SFK", "Amedspor"), ("Amed",)),
    Team("Çorum FK", ("Corum FK",), ("Çorum",)),
    Team("Antalyaspor", ("Antalyaspor",), ("Antalya",)),
    Team("Sivasspor", ("Sivasspor",), ("Sivas",)),
    Team("Kayserispor", ("Kayserispor",), ("Kayseri",)),
    Team("Hatayspor", ("Hatayspor",), ("Hatay",)),
    Team("Adana Demirspor", ("Adana Demirspor",), ("Demirspor",)),
    Team("Ankaragücü", ("MKE Ankaragucu", "Ankaragucu"), ()),
    Team("Fatih Karagümrük", ("Fatih Karagumruk", "Karagumruk"), ("Karagümrük",)),
    Team("Bodrum FK", ("Bodrum FK", "Bodrumspor"), ("Bodrum", "Bodrumspor")),
    Team("Pendikspor", ("Pendikspor",), ("Pendik",)),
    Team("İstanbulspor", ("Istanbulspor",)),
    Team("Bandırmaspor", ("Bandirmaspor",), ("Bandırma",)),
    Team("Manisa FK", ("Manisa FK",), ()),
)

_BY_ESPN = {folded(name): team for team in TEAMS for name in team.espn}


def from_espn(name: str) -> Team | None:
    return _BY_ESPN.get(folded(name))


def display_name(espn_name: str) -> str:
    """The Turkish name for an ESPN team name; ESPN's own when the club isn't in the table."""
    team = from_espn(espn_name)
    return team.name if team else espn_name


def mentioned(command: str) -> Team | None:
    """ "Galatasaray'ın maçı kaç kaç", "GS maçı", "Fener ne zaman oynuyor"."""
    names = [(spelling, team) for team in TEAMS for spelling in (team.name, *team.espn, *team.aliases)]
    return spoken_names.find(command, names)


def named(name: str) -> Team | None:
    """A team from the model's argument: the whole of it must be one of the team's names."""
    key = folded(name)
    return next(
        (team for team in TEAMS if key in {folded(n) for n in (team.name, *team.espn, *team.aliases)}), None
    ) or mentioned(name)
