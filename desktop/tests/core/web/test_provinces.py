import pytest

from bilge.core.web import provinces


def test_there_are_81_provinces_with_their_centres_in_turkiye():
    assert len(provinces.PROVINCES) == len({p.name for p in provinces.PROVINCES}) == 81
    assert all(35.8 < p.latitude < 42.2 and 25.9 < p.longitude < 44.9 for p in provinces.PROVINCES)


def test_distance_between_two_centres():
    istanbul, ankara = provinces.named("istanbul"), provinces.named("Ankara")
    distance = provinces.distance_km(istanbul.latitude, istanbul.longitude, ankara.latitude, ankara.longitude)
    assert 340 < distance < 360
    assert provinces.distance_km(1, 2, 1, 2) == 0


@pytest.mark.parametrize(
    ("command", "province"),
    [
        ("İzmir'de deprem var mı", "İzmir"),
        ("izmirde deprem var mi", "İzmir"),
        ("Ankara'daki son depremler", "Ankara"),
        ("Maraş'ta deprem oldu mu", "Kahramanmaraş"),
        ("Muğla yakınında deprem", "Muğla"),
        ("was there an earthquake near Istanbul", "İstanbul"),
        ("deprem karşısında ne yapmalı", None),
        ("son depremler", None),
        ("deprem oldu mu biliyor musun", None),
        ("Muş'un çevresinde deprem var mı", "Muş"),
    ],
)
def test_a_province_said_in_a_command(command, province):
    found = provinces.mentioned(command)
    assert (found.name if found else None) == province


def test_names_and_aliases():
    assert provinces.named("İZMİR").name == "İzmir"
    assert provinces.named("Afyon").name == "Afyonkarahisar"
    assert provinces.named("Berlin") is None
