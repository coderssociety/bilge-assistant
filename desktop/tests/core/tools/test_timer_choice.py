from dataclasses import dataclass

from bilge.core.tools import timer_choice


@dataclass(frozen=True)
class T:
    label: str | None


TEA, EGGS, BARE = T("çay"), T("yumurta"), T(None)


def test_a_label_picks_the_timer_it_names():
    assert timer_choice.chosen([TEA, EGGS, BARE], "çay", None) == [TEA]
    assert timer_choice.chosen([TEA, EGGS], "Çayın zamanlayıcısı", None) == [TEA]
    assert timer_choice.chosen([TEA, EGGS], "makarna", None) == []


def test_a_position_picks_that_timer():
    assert timer_choice.chosen([TEA, EGGS], None, 2) == [EGGS]
    assert timer_choice.chosen([TEA, EGGS], None, 3) == []


def test_nothing_named_means_all_and_generic_words_name_nothing():
    assert timer_choice.chosen([TEA, BARE], None, None) == [TEA, BARE]
    assert timer_choice.chosen([TEA, BARE], "zamanlayıcı", None) == [TEA, BARE]


def test_time_left_keeps_seconds_only_near_the_end():
    assert timer_choice.split_duration(270) == (0, 4, 30)
    assert timer_choice.split_duration(45) == (0, 0, 45)
    assert timer_choice.split_duration(3 * 3600 + 5 * 60 + 40) == (3, 6, 0)
    assert timer_choice.split_duration(-3) == (0, 0, 0)
