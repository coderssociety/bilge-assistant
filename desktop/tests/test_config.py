import pytest

from bilge import cli, config
from bilge.core.language import AssistantLanguage


def test_settings_round_trip(tmp_path):
    path = tmp_path / "settings.json"
    settings = config.Settings(language="en", model=config.ModelSettings("openrouter", "some/model"))
    config.save_settings(settings, path)
    loaded = config.load_settings(path)
    assert loaded == settings
    assert loaded.assistant_language is AssistantLanguage.ENGLISH


def test_missing_file_gives_defaults(tmp_path):
    assert config.load_settings(tmp_path / "none.json") == config.Settings()


def test_unknown_language_falls_back_to_turkish():
    assert config.Settings(language="xx").assistant_language is AssistantLanguage.TURKISH


def test_broken_file_is_an_error_not_silently_reset(tmp_path):
    path = tmp_path / "settings.json"
    path.write_text("{not json", encoding="utf-8")
    with pytest.raises(RuntimeError, match="Could not read"):
        config.load_settings(path)


def test_api_key_falls_back_to_the_environment(monkeypatch):
    monkeypatch.setattr(config.keyring, "get_password", lambda *_: None)
    monkeypatch.setenv("OPENROUTER_API_KEY", "from-env")
    assert config.api_key("openrouter") == "from-env"
    assert config.api_key("lmstudio") is None


def test_calendar_settings_round_trip(tmp_path):
    path = tmp_path / "settings.json"
    settings = config.Settings(calendar=config.CalendarSettings("caldav", "https://dav.example.org/", "ayse", "İş"))
    config.save_settings(settings, path)
    assert config.load_settings(path).calendar == settings.calendar


def test_mail_settings_round_trip(tmp_path):
    path = tmp_path / "settings.json"
    settings = config.Settings(mail=config.MailSettings("imap.example.org:993", "ayse@example.org"))
    config.save_settings(settings, path)
    assert config.load_settings(path).mail == settings.mail


def test_home_assistant_settings_round_trip_without_the_token(tmp_path):
    path = tmp_path / "settings.json"
    settings = config.Settings(home=config.HomeSettings("http://homeassistant.local:8123"))
    config.save_settings(settings, path)
    assert config.load_settings(path).home == settings.home
    assert config.load_settings(tmp_path / "missing.json").home == config.HomeSettings()


def test_a_file_saved_with_a_byte_order_mark_is_read(tmp_path):
    path = tmp_path / "settings.json"
    path.write_bytes(b"\xef\xbb\xbf" + b'{"language": "en", "setup_done": true}')
    loaded = config.load_settings(path)
    assert loaded.language == "en" and loaded.setup_done


def test_how_bilge_is_called_and_where_whisper_runs_round_trip(tmp_path):
    path = tmp_path / "settings.json"
    settings = config.Settings(check_updates=False)
    settings.voice.wake_word, settings.voice.hotkey, settings.voice.accelerator = False, "Ctrl+Shift+B", "gpu"
    config.save_settings(settings, path)
    assert config.load_settings(path) == settings


def test_a_hand_edited_file_never_leaves_bilge_uncallable(tmp_path):
    path = tmp_path / "settings.json"
    path.write_text('{"voice": {"wake_word": false, "hotkey": "", "accelerator": "quantum"}}', encoding="utf-8")
    voice = config.load_settings(path).voice
    assert voice.wake_word and voice.accelerator == "auto"


def test_an_older_settings_file_gets_the_new_defaults(tmp_path):
    path = tmp_path / "settings.json"
    path.write_text('{"language": "tr", "voice": {"recognizer": "local"}}', encoding="utf-8")
    loaded = config.load_settings(path)
    assert loaded.check_updates and loaded.voice.wake_word
    assert (loaded.voice.hotkey, loaded.voice.accelerator) == ("", "auto")
    assert loaded.earthquake_alerts


def test_earthquake_alerts_can_be_turned_off(tmp_path):
    path = tmp_path / "settings.json"
    config.save_settings(config.Settings(earthquake_alerts=False), path)
    assert config.load_settings(path).earthquake_alerts is False


def test_custom_commands_round_trip_and_broken_entries_are_dropped(tmp_path):
    path = tmp_path / "settings.json"
    backup = config.CustomCommand("yedekleme", ["rsync", "-a", "/home/ayse/Belgeler", "/mnt/yedek"])
    config.save_settings(config.Settings(commands=[backup]), path)
    assert config.load_settings(path).commands == [backup]
    path.write_text(
        '{"commands": [{"name": "boş", "argv": []}, {"name": "", "argv": ["ls"]}, {"name": "x", "argv": "ls -l"},'
        ' {"name": "sayı", "argv": ["ls", 3]}, "metin", {"name": " liste ", "argv": ["ls", "-l"]}]}',
        encoding="utf-8",
    )
    assert config.load_settings(path).commands == [config.CustomCommand("liste", ["ls", "-l"])]


def test_the_music_service_round_trips_and_an_unknown_one_is_auto(tmp_path):
    path = tmp_path / "settings.json"
    config.save_settings(config.Settings(music_service="deezer"), path)
    assert config.load_settings(path).music_service == "deezer"
    path.write_text('{"music_service": "napster"}', encoding="utf-8")
    assert config.load_settings(path).music_service == "auto"


def test_the_music_service_is_shown_and_set_on_the_command_line(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(config, "settings_path", lambda: tmp_path / "settings.json")
    assert cli.main(["music", "youtube"]) == 0
    assert config.load_settings().music_service == "youtube"
    assert cli.main(["music"]) == 0
    assert capsys.readouterr().out.split() == ["youtube", "youtube"]
