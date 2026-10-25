import pytest

from bilge.core.web import turkish_provinces


def test_has_all_81_provinces_by_plate():
    assert len(turkish_provinces.PROVINCES) == 81
    assert [p.plate for p in turkish_provinces.PROVINCES] == list(range(1, 82))
    assert turkish_provinces.by_plate(35).name == "İzmir"
    assert turkish_provinces.by_plate(81).name == "Düzce"
    assert turkish_provinces.by_plate(99) is None


@pytest.mark.parametrize(
    ("command", "plate"),
    [
        ("İzmir'de motorin", 35),
        ("Ankara'nın namaz vakitleri", 6),
        ("Şanlıurfa'ya", 63),
        ("Urfa'da benzin", 63),
        ("Afyon'da LPG", 3),
        ("Kahramanmaraş'ta iftar", 46),
        ("ISTANBUL", 34),
        ("Iğdır'da ezan", 76),
        ("Kırıkkale ve Kırklareli", 71),
        ("petrol price in Istanbul", 34),
        ("Istanbul's prayer times", 34),
        ("Muş'un hava durumu", 49),
        ("Muş'ta benzin kaç lira", 49),
    ],
)
def test_finds_a_province_with_its_case_ending(command, plate):
    assert turkish_provinces.find(command).plate == plate


@pytest.mark.parametrize(
    "command",
    ["benzin ne kadar", "akşam ezanı kaçta", "Kartal'da hava", "Vanessa", "vanilya", "benzin fiyatını bulur musun",
     "akşam ezanı ne zaman biliyor musun", "bulur musunuz"],
)  # fmt: skip
def test_finds_nothing_where_no_province_is_named(command):
    assert turkish_provinces.find(command) is None
