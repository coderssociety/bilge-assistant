import pytest

from bilge.core.language import AssistantLanguage
from bilge.core.tools.custom_command import (
    asks_for_list,
    best_match,
    fingerprint,
    join_command_line,
    run_request,
    split_command_line,
)

EN = AssistantLanguage.ENGLISH
TR = AssistantLanguage.TURKISH


@pytest.mark.parametrize(
    ("command", "language", "name"),
    [
        ("yedekleme komutunu çalıştır", TR, "yedekleme"),
        ("Bilge, sunucu güncelleme komutunu çalıştırır mısın", TR, "sunucu güncelleme"),
        ("lütfen yedek komutu başlat", TR, "yedek"),
        ("komutunu çalıştır", TR, None),
        ("yedekleme yap", TR, None),
        ("run the backup command", EN, "backup"),
        ("please run my server update command now", EN, "server update"),
        ("run backup", EN, None),
    ],
)
def test_the_name_of_the_command_to_run_is_read_from_the_words(command, language, name):
    assert run_request(command, language) == name


@pytest.mark.parametrize(
    ("command", "language", "expected"),
    [
        ("komutlarım neler", TR, True),
        ("hangi komutlarım var", TR, True),
        ("komutlarımı listele", TR, True),
        ("hangi komutları biliyorsun", TR, False),
        ("yedekleme komutunu çalıştır", TR, False),
        ("list my commands", EN, True),
        ("what custom commands do I have", EN, True),
        ("what commands do you know", EN, False),
    ],
)
def test_asking_for_the_users_own_commands(command, language, expected):
    assert asks_for_list(command, language) is expected


def test_the_configured_name_is_found_with_the_command_word_said_along():
    names = ["Yedekleme", "Sunucu güncelleme"]
    assert best_match("yedekleme komutunu", names) == "Yedekleme"
    assert best_match("sunucu güncellemesi", names) == "Sunucu güncelleme"
    assert best_match("müzik", names) is None


def test_an_approval_is_bound_to_the_exact_command():
    original = fingerprint("yedek", ["rsync", "-a", "/a", "/b"])
    assert original == fingerprint("yedek", ["rsync", "-a", "/a", "/b"])
    assert original != fingerprint("yedek", ["rsync", "-a", "/a", "/c"])
    assert original != fingerprint("yedek", ["rsync", "-a /a", "/b"])
    assert original != fingerprint("yedek2", ["rsync", "-a", "/a", "/b"])


@pytest.mark.parametrize(
    ("line", "windows", "argv"),
    [
        ("rsync -a '/home/ayşe/Belgeler' /mnt/yedek", False, ["rsync", "-a", "/home/ayşe/Belgeler", "/mnt/yedek"]),
        ('notify-send "Merhaba dünya" #1', False, ["notify-send", "Merhaba dünya", "#1"]),
        (r'"C:\Program Files\Yedek\yedek.exe" /tam C:\Belgeler', True,
         [r"C:\Program Files\Yedek\yedek.exe", "/tam", r"C:\Belgeler"]),
    ],
)  # fmt: skip
def test_command_lines_split_into_arguments_and_back(line, windows, argv):
    assert split_command_line(line, windows) == argv
    assert split_command_line(join_command_line(argv, windows), windows) == argv


def test_an_unclosed_quote_is_an_error():
    with pytest.raises(ValueError):
        split_command_line("echo 'yarım", windows=False)
