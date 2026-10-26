import pytest

from bilge.core.tools import volume_amount
from bilge.core.tools.volume_amount import Amount


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("sesi yüzde 20 artır", Amount(20, target=False)),
        ("sesi 15 puan kıs", Amount(15, target=False)),
        ("sesi %30 yap", Amount(30, target=False)),
        ("sesi yüzde 80'e çıkar", Amount(80, target=True)),
        ("sesi yüzde 50ye getir", Amount(50, target=True)),
        ("turn it up by 15 percent", Amount(15, target=False)),
        ("turn the volume up to 80", Amount(80, target=True)),
        ("sesi yüzde 300 yap", Amount(100, target=False)),
    ],
)
def test_reads_the_amount_and_whether_it_is_the_level_to_reach(text, expected):
    assert volume_amount.read(text) == expected


def test_no_number_is_no_amount():
    assert volume_amount.read("sesi biraz aç") is None
